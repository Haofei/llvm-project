// RUN: mlir-opt --test-emulate-narrow-int="arith-compute-bitwidth=1 memref-load-bitwidth=8" --cse --split-input-file %s | FileCheck %s

// TODO: remove memref.alloc() in the tests to eliminate noises.
// memref.alloc exists here because sub-byte vector data types such as i2
// are currently not supported as input arguments.


func.func @vector_load_i2() -> vector<3x3xi2> {
  %0 = memref.alloc() : memref<3x3xi2>
  %c0 = arith.constant 0 : index
  %c2 = arith.constant 2 : index
  %cst = arith.constant dense<0> : vector<3x3xi2>
  %1 = vector.load %0[%c2, %c0] : memref<3x3xi2>, vector<3xi2>
  %2 = vector.insert %1, %cst [0] : vector<3xi2> into vector<3x3xi2>
  return %2 : vector<3x3xi2>
}

// CHECK-LABEL: func @vector_load_i2
// CHECK: %[[ALLOC:.+]] = memref.alloc() : memref<3xi8>
// CHECK: %[[INDEX:.+]] = arith.constant 1 : index
// CHECK: %[[VEC:.+]] = vector.load %[[ALLOC]][%[[INDEX]]] : memref<3xi8>, vector<2xi8>
// CHECK: %[[VEC_I2:.+]] = vector.bitcast %[[VEC]] : vector<2xi8> to vector<8xi2>
// CHECK: %[[EXCTRACT:.+]] = vector.extract_strided_slice %[[VEC_I2]] {offsets = [2], sizes = [3], strides = [1]} : vector<8xi2> to vector<3xi2>

// -----

func.func @vector_transfer_read_i2() -> vector<3xi2> {
  %0 = memref.alloc() : memref<3x3xi2>
  %pad = arith.constant 0 : i2
  %c0 = arith.constant 0 : index
  %c2 = arith.constant 2 : index
  %1 = vector.transfer_read %0[%c2, %c0], %pad {in_bounds = [true]} : memref<3x3xi2>, vector<3xi2>
  return %1 : vector<3xi2>
}

// CHECK-LABEL: func @vector_transfer_read_i2
// CHECK: %[[ALLOC:.+]] = memref.alloc() : memref<3xi8>
// CHECK: %[[INDEX:.+]] = arith.constant 1 : index
// CHECK: %[[READ:.+]] = vector.transfer_read %[[ALLOC]][%[[INDEX]]], %0 : memref<3xi8>, vector<2xi8>
// CHECK: %[[BITCAST:.+]] = vector.bitcast %[[READ]] : vector<2xi8> to vector<8xi2>
// CHECK: vector.extract_strided_slice %[[BITCAST]] {offsets = [2], sizes = [3], strides = [1]} : vector<8xi2> to vector<3xi2>

// -----

func.func @vector_constant_mask_maskedload_i2(%passthru: vector<5xi2>) -> vector<5xi2> {
  %0 = memref.alloc() : memref<3x5xi2>
  %mask = vector.constant_mask [3] : vector<5xi1>
  %c0 = arith.constant 0 : index
  %c2 = arith.constant 2 : index
  %1 = vector.maskedload %0[%c2, %c0], %mask, %passthru :
    memref<3x5xi2>, vector<5xi1>, vector<5xi2> into vector<5xi2>
  return %1 : vector<5xi2>
}
// CHECK-LABEL: func @vector_constant_mask_maskedload_i2(
// CHECK-SAME: %[[ARG0:.+]]: vector<5xi2>) -> vector<5xi2>
// CHECK: %[[ALLOC:.+]] = memref.alloc() : memref<4xi8>
// CHECK: %[[ORIGINMASK:.+]] = vector.constant_mask [3] : vector<5xi1>
// CHECK: %[[NEWMASK:.+]] = vector.constant_mask [2] : vector<2xi1>
// CHECK: %[[VESSEL:.+]] = arith.constant dense<0> : vector<8xi2>
// CHECK: %[[INSERT1:.+]] = vector.insert_strided_slice %[[ARG0]], %[[VESSEL]]
// CHECK-SAME: {offsets = [2], strides = [1]} : vector<5xi2> into vector<8xi2>
// CHECK: %[[BITCAST1:.+]] = vector.bitcast %[[INSERT1]] : vector<8xi2> to vector<2xi8>
// CHECK: %[[C2:.+]] = arith.constant 2 : index
// CHECK: %[[MASKEDLOAD:.+]] = vector.maskedload %alloc[%[[C2]]], %[[NEWMASK:.+]], %[[BITCAST1]]
// CHECK-SAME: : memref<4xi8>, vector<2xi1>, vector<2xi8> into vector<2xi8>
// CHECK: %[[BITCAST2:.+]] = vector.bitcast %[[MASKEDLOAD]] : vector<2xi8> to vector<8xi2>
// CHECK: %[[CST2:.+]] = arith.constant dense<false> : vector<8xi1>
// CHECK: %[[INSERT2:.+]] = vector.insert_strided_slice %[[ORIGINMASK]], %[[CST2]]
// CHECK-SAME: {offsets = [2], strides = [1]} : vector<5xi1> into vector<8xi1>
// CHECK: %[[SELECT:.+]] = arith.select %[[INSERT2]], %[[BITCAST2]], %[[INSERT1]] : vector<8xi1>, vector<8xi2>
// CHECK: vector.extract_strided_slice %[[SELECT]] {offsets = [2], sizes = [5], strides = [1]} : vector<8xi2> to vector<5xi2>

// -----

// This tests the correctness of generating compressed mask with `vector.create_mask` on a static input and dynamic indices.
// Specifically, the program masked loads a vector<5xi2> from `vector<3x5xi2>[1, 0]`, with an unknown mask generator `m`.
// After emulation transformation, it masked loads 2 bytes from linearized index `vector<4xi8>[1]`, with a new compressed mask
// given by `ceildiv(m + 1, 4)`.
func.func @unaligned_create_mask_dynamic_i2(%m : index, %passthru: vector<5xi2>) -> vector<5xi2> {
    %0 = memref.alloc() : memref<3x5xi2>
    %c0 = arith.constant 0 : index
    %c1 = arith.constant 1 : index
    %mask = vector.create_mask %m : vector<5xi1>
    %1 = vector.maskedload %0[%c1, %c0], %mask, %passthru :
      memref<3x5xi2>, vector<5xi1>, vector<5xi2> into vector<5xi2>
    return %1 : vector<5xi2>
}

// CHECK-DAG: #[[MAP:.+]] = affine_map<()[s0] -> ((s0 + 1) ceildiv 4)>
// CHECK: func @unaligned_create_mask_dynamic_i2(
// CHECK-SAME:  %[[NUM_ELEMS_TO_LOAD:.+]]: index, %[[PASSTHRU:.+]]: vector<5xi2>)
// CHECK: %[[ALLOC:.+]] = memref.alloc() : memref<4xi8>
// CHECK: %[[COMPRESSED_MASK:.+]] = affine.apply #map()[%[[NUM_ELEMS_TO_LOAD]]]
// CHECK: vector.create_mask %[[COMPRESSED_MASK]] : vector<2xi1>
// CHECK: %[[C1:.+]] = arith.constant 1 : index
// CHECK: vector.maskedload %[[ALLOC]][%[[C1]]]

// -----

// This tests the correctness of generated compressed mask with `vector.create_mask`, and a static input.
// Quite the same as the previous test, but the mask generator is a static value.
// In this case, the desired slice `vector<7xi2>` spans over 3 bytes.
func.func @check_unaligned_create_mask_static_i2(%passthru: vector<7xi2>) -> vector<7xi2> {
    %0 = memref.alloc() : memref<3x7xi2>
    %c0 = arith.constant 0 : index
    %c1 = arith.constant 1 : index
    %c3 = arith.constant 3 : index
    %mask = vector.create_mask %c3 : vector<7xi1>
    %1 = vector.maskedload %0[%c1, %c0], %mask, %passthru :
      memref<3x7xi2>, vector<7xi1>, vector<7xi2> into vector<7xi2>
    return %1 : vector<7xi2>
}

// CHECK: func @check_unaligned_create_mask_static_i2(
// CHECK-SAME:     %[[PASSTHRU:[a-zA-Z0-9]+]]: vector<7xi2>)
// CHECK: %[[ALLOC:.+]] = memref.alloc() : memref<6xi8>
// CHECK: %[[C2:.+]] = arith.constant 2 : index
// CHECK: %[[COMP_MASK:.+]] = vector.create_mask %[[C2]] : vector<3xi1>
// CHECK: %[[C1:.+]] = arith.constant 1 : index
// CHECK: %4 = vector.maskedload %[[ALLOC]][%[[C1]]], %[[COMP_MASK]]

// -----

// This test is similar to @vector_constant_mask_maskedload_i2, but the mask is multi-dimensional.
func.func @vector_constant_mask_maskedload_i2_multidim(%passthru: vector<5xi2>) -> vector<5xi2> {
  %0 = memref.alloc() : memref<4x3x5xi2>
  %mask = vector.constant_mask [2, 2] : vector<3x5xi1>
  %ext_mask = vector.extract %mask[1] : vector<5xi1> from vector<3x5xi1>
  %c0 = arith.constant 0 : index
  %c2 = arith.constant 2 : index
  %1 = vector.maskedload %0[%c2, %c0, %c0], %ext_mask, %passthru :
    memref<4x3x5xi2>, vector<5xi1>, vector<5xi2> into vector<5xi2>
  return %1 : vector<5xi2>
}

// CHECK-LABEL: func @vector_constant_mask_maskedload_i2_multidim(
// CHECK: %[[ORIG_MASK:.+]] = vector.constant_mask [2, 2] : vector<3x5xi1>
// CHECK: vector.extract %[[ORIG_MASK]][1]

// Compressing the mask used for emulated masked load.
// The innermost dimension is compressed to 2 elements from 5.
// CHECK: %[[NEW_COMPRESSED_MASK:.+]] = vector.constant_mask [2, 1] : vector<3x2xi1>
// CHECK: vector.extract %[[NEW_COMPRESSED_MASK]][1]

// -----

func.func @vector_load_i2_dynamic_indexing(%idx1: index, %idx2: index) -> vector<3xi2> {
  %0 = memref.alloc() : memref<3x3xi2>
  %cst = arith.constant dense<0> : vector<3x3xi2>
  %1 = vector.load %0[%idx1, %idx2] : memref<3x3xi2>, vector<3xi2>
  return %1 : vector<3xi2>
}

// CHECK: #[[MAP:.+]] = affine_map<()[s0, s1] -> ((s0 * 3 + s1) floordiv 4)>
// CHECK: #[[MAP1:.+]] = affine_map<()[s0, s1] -> ((s0 * 3 + s1) mod 4)>
// CHECK: func @vector_load_i2_dynamic_indexing(
// CHECK-SAME: %[[ARG0:.+]]: index, %[[ARG1:.+]]: index) -> vector<3xi2>
// CHECK: %[[ALLOC:.+]]= memref.alloc() : memref<3xi8>
// CHECK: %[[LOADADDR1:.+]] = affine.apply #[[MAP]]()[%[[ARG0]], %[[ARG1]]]
// CHECK: %[[LOADADDR2:.+]] = affine.apply #[[MAP1]]()[%[[ARG0]], %[[ARG1]]]
// CHECK: %[[EMULATED_LOAD:.+]] = vector.load %alloc[%[[LOADADDR1]]] : memref<3xi8>, vector<2xi8>
// CHECK: %[[BITCAST:.+]] = vector.bitcast %[[EMULATED_LOAD]] : vector<2xi8> to vector<8xi2>
// CHECK: %[[ZERO:.+]] = arith.constant dense<0> : vector<3xi2>
// CHECK: %[[EXTRACT:.+]] = vector.extract %[[BITCAST]][%[[LOADADDR2]]] : i2 from vector<8xi2>
// CHECK: %[[C1:.+]] = arith.constant 1 : index
// CHECK: %[[OFFSET:.+]] = arith.addi %[[LOADADDR2]], %[[C1]] : index
// CHECK: %[[EXTRACT2:.+]] = vector.extract %[[BITCAST]][%[[OFFSET]]] : i2 from vector<8xi2>
// CHECK: %[[C2:.+]] = arith.constant 2 : index
// CHECK: %[[OFFSET2:.+]] = arith.addi %1, %c2 : index
// CHECK: %[[EXTRACT3:.+]] = vector.extract %[[BITCAST]][%[[OFFSET2]]] : i2 from vector<8xi2>

// -----

func.func @vector_load_i2_dynamic_indexing_mixed(%idx: index) -> vector<3xi2> {
  %0 = memref.alloc() : memref<3x3xi2>
  %c2 = arith.constant 2 : index
  %cst = arith.constant dense<1> : vector<3x3xi2>
  %1 = vector.load %0[%idx, %c2] : memref<3x3xi2>, vector<3xi2>
  return %1 : vector<3xi2>
}

// CHECK: #[[MAP:.+]] = affine_map<()[s0] -> ((s0 * 3 + 2) floordiv 4)>
// CHECK: #[[MAP1:.+]] = affine_map<()[s0] -> (s0 * 3 - ((s0 * 3 + 2) floordiv 4) * 4 + 2)>
// CHECK: func @vector_load_i2_dynamic_indexing_mixed(
// CHECK-SAME: %[[ARG0:.+]]: index) -> vector<3xi2>
// CHECK: %[[ALLOC:.+]]= memref.alloc() : memref<3xi8>
// CHECK: %[[LOADADDR1:.+]] = affine.apply #[[MAP]]()[%[[ARG0]]]
// CHECK: %[[LOADADDR2:.+]] = affine.apply #[[MAP1]]()[%[[ARG0]]]
// CHECK: %[[EMULATED_LOAD:.+]] = vector.load %alloc[%[[LOADADDR1]]] : memref<3xi8>, vector<2xi8>
// CHECK: %[[BITCAST:.+]] = vector.bitcast %[[EMULATED_LOAD]] : vector<2xi8> to vector<8xi2>
// CHECK: %[[ZERO:.+]] = arith.constant dense<0> : vector<3xi2>
// CHECK: %[[EXTRACT:.+]] = vector.extract %[[BITCAST]][%[[LOADADDR2]]] : i2 from vector<8xi2>
// CHECK: %[[C1:.+]] = arith.constant 1 : index
// CHECK: %[[OFFSET:.+]] = arith.addi %[[LOADADDR2]], %[[C1]] : index
// CHECK: %[[EXTRACT2:.+]] = vector.extract %[[BITCAST]][%[[OFFSET]]] : i2 from vector<8xi2>
// CHECK: %[[C2:.+]] = arith.constant 2 : index
// CHECK: %[[OFFSET2:.+]] = arith.addi %1, %c2 : index
// CHECK: %[[EXTRACT3:.+]] = vector.extract %[[BITCAST]][%[[OFFSET2]]] : i2 from vector<8xi2>

// -----

func.func @vector_transfer_read_i2_dynamic_indexing(%idx1: index, %idx2: index) -> vector<3xi2> {
  %0 = memref.alloc() : memref<3x3xi2>
  %pad = arith.constant 0 : i2
  %1 = vector.transfer_read %0[%idx1, %idx2], %pad {in_bounds = [true]} : memref<3x3xi2>, vector<3xi2>
  return %1 : vector<3xi2>
}

// CHECK: #[[MAP:.+]] = affine_map<()[s0, s1] -> ((s0 * 3 + s1) floordiv 4)>
// CHECK: #[[MAP1:.+]] = affine_map<()[s0, s1] -> ((s0 * 3 + s1) mod 4)>
// CHECK: func @vector_transfer_read_i2_dynamic_indexing(
// CHECK-SAME: %[[ARG0:.+]]: index, %[[ARG1:.+]]: index) -> vector<3xi2>
// CHECK: %[[ALLOC:.+]] = memref.alloc() : memref<3xi8>
// CHECK: %[[C0:.+]] = arith.extui %c0_i2 : i2 to i8
// CHECK: %[[LOADADDR1:.+]] = affine.apply #[[MAP]]()[%[[ARG0]], %[[ARG1]]]
// CHECK: %[[LOADADDR2:.+]] = affine.apply #[[MAP1]]()[%[[ARG0]], %[[ARG1]]]
// CHECK: %[[READ:.+]] = vector.transfer_read %[[ALLOC]][%[[LOADADDR1]]], %[[C0]] : memref<3xi8>, vector<2xi8>
// CHECK: %[[BITCAST:.+]] = vector.bitcast %[[READ]] : vector<2xi8> to vector<8xi2>
// CHECK: %[[CST:.+]] = arith.constant dense<0> : vector<3xi2>
// CHECK: %[[EXTRACT:.+]] = vector.extract %[[BITCAST]][%[[LOADADDR2]]] : i2 from vector<8xi2>
// CHECK: %[[C1:.+]] = arith.constant 1 : index
// CHECK: %[[ADDI:.+]] = arith.addi %[[LOADADDR2]], %[[C1]] : index
// CHECK: %[[EXTRACT2:.+]] = vector.extract %[[BITCAST]][%[[ADDI]]] : i2 from vector<8xi2>
// CHECK: %[[C2:.+]] = arith.constant 2 : index
// CHECK: %[[ADDI2:.+]] = arith.addi %[[LOADADDR2]], %[[C2]] : index
// CHECK: %[[EXTRACT3:.+]] = vector.extract %[[BITCAST]][%[[ADDI2]]] : i2 from vector<8xi2>

// -----

func.func @vector_transfer_read_i2_dynamic_indexing_mixed(%idx1: index) -> vector<3xi2> {
  %0 = memref.alloc() : memref<3x3xi2>
  %c2 = arith.constant 2 : index
  %pad = arith.constant 0 : i2
  %1 = vector.transfer_read %0[%idx1, %c2], %pad {in_bounds = [true]} : memref<3x3xi2>, vector<3xi2>
  return %1 : vector<3xi2>
}

// CHECK: #[[MAP:.+]] = affine_map<()[s0] -> ((s0 * 3 + 2) floordiv 4)>
// CHECK: #[[MAP1:.+]] = affine_map<()[s0] -> (s0 * 3 - ((s0 * 3 + 2) floordiv 4) * 4 + 2)>
// CHECK: func @vector_transfer_read_i2_dynamic_indexing_mixed(
// CHECK-SAME: %[[ARG0:.+]]: index) -> vector<3xi2>
// CHECK: %[[ALLOC:.+]] = memref.alloc() : memref<3xi8>
// CHECK: %[[C0:.+]] = arith.extui %c0_i2 : i2 to i8
// CHECK: %[[LOADADDR1:.+]] = affine.apply #[[MAP]]()[%[[ARG0]]]
// CHECK: %[[LOADADDR2:.+]] = affine.apply #[[MAP1]]()[%[[ARG0]]]
// CHECK: %[[READ:.+]] = vector.transfer_read %[[ALLOC]][%[[LOADADDR1]]], %[[C0]] : memref<3xi8>, vector<2xi8>
// CHECK: %[[BITCAST:.+]] = vector.bitcast %[[READ]] : vector<2xi8> to vector<8xi2>
// CHECK: %[[CST:.+]] = arith.constant dense<0> : vector<3xi2>
// CHECK: %[[EXTRACT:.+]] = vector.extract %[[BITCAST]][%[[LOADADDR2]]] : i2 from vector<8xi2>
// CHECK: %[[C1:.+]] = arith.constant 1 : index
// CHECK: %[[ADDI:.+]] = arith.addi %[[LOADADDR2]], %[[C1]] : index
// CHECK: %[[EXTRACT2:.+]] = vector.extract %[[BITCAST]][%[[ADDI]]] : i2 from vector<8xi2>
// CHECK: %[[C2:.+]] = arith.constant 2 : index
// CHECK: %[[ADDI2:.+]] = arith.addi %[[LOADADDR2]], %[[C2]] : index
// CHECK: %[[EXTRACT3:.+]] = vector.extract %[[BITCAST]][%[[ADDI2]]] : i2 from vector<8xi2>
// -----

func.func @vector_maskedload_i2_dynamic_indexing_mixed(%passthru: vector<3xi2>, %idx: index) -> vector<3xi2> {
  %0 = memref.alloc() : memref<3x3xi2>
  %cst = arith.constant dense<0> : vector<3x3xi2>
  %c2 = arith.constant 2 : index
  %mask = vector.constant_mask [3] : vector<3xi1>
  %1 = vector.maskedload %0[%idx, %c2], %mask, %passthru :
    memref<3x3xi2>, vector<3xi1>, vector<3xi2> into vector<3xi2>
  return %1 : vector<3xi2>
}

// CHECK: #[[MAP:.+]] = affine_map<()[s0] -> ((s0 * 3 + 2) floordiv 4)>
// CHECK: #[[MAP1:.+]] = affine_map<()[s0] -> (s0 * 3 - ((s0 * 3 + 2) floordiv 4) * 4 + 2)>
// CHECK: func @vector_maskedload_i2_dynamic_indexing_mixed(
// CHECK-SAME: %[[PTH:.+]]: vector<3xi2>, %[[IDX:.+]]: index) -> vector<3xi2>
// CHECK: %[[ALLOC:.+]] = memref.alloc() : memref<3xi8>
// CHECK: %[[MASK:.+]] = vector.constant_mask [3] : vector<3xi1>
// CHECK: %[[LINEAR1:.+]] = affine.apply #map()[%[[IDX]]]
// CHECK: %[[LINEAR2:.+]] = affine.apply #map1()[%[[IDX]]]
// CHECK: %[[ONE:.+]] = vector.constant_mask [2] : vector<2xi1>
// CHECK: %[[ZERO:.+]] = arith.constant dense<0> : vector<8xi2>

// Extract passthru vector, and insert into zero vector, this is for constructing a new passthru
// CHECK: %[[EX1:.+]] = vector.extract %[[PTH]][0] : i2 from vector<3xi2>
// CHECK: %[[IN1:.+]] = vector.insert %[[EX1]], %[[ZERO]] [%[[LINEAR2]]] : i2 into vector<8xi2>
// CHECK: %[[C1:.+]] = arith.constant 1 : index
// CHECK: %[[INCIDX:.+]] = arith.addi %[[LINEAR2]], %[[C1]] : index
// CHECK: %[[EX2:.+]] = vector.extract %[[PTH]][1] : i2 from vector<3xi2>
// CHECK: %[[IN2:.+]] = vector.insert %[[EX2]], %[[IN1]] [%[[INCIDX]]] : i2 into vector<8xi2>
// CHECK: %[[C2:.+]] = arith.constant 2 : index
// CHECK: %[[INCIDX2:.+]] = arith.addi %[[LINEAR2]], %[[C2]] : index
// CHECK: %[[EX3:.+]] = vector.extract %[[PTH]][2] : i2 from vector<3xi2>
// CHECK: %[[NEW_PASSTHRU:.+]] = vector.insert %[[EX3]], %[[IN2]] [%[[INCIDX2]]] : i2 into vector<8xi2>

// Bitcast the new passthru vector to emulated i8 vector
// CHECK: %[[BCAST_PASSTHRU:.+]] = vector.bitcast %[[NEW_PASSTHRU]] : vector<8xi2> to vector<2xi8>

// Use the emulated i8 vector for masked load from the source memory
// CHECK: %[[SOURCE:.+]] = vector.maskedload %[[ALLOC]][%[[LINEAR1]]], %[[ONE]], %[[BCAST_PASSTHRU]]
// CHECK-SAME: memref<3xi8>, vector<2xi1>, vector<2xi8> into vector<2xi8>

// Bitcast back to i2 vector
// CHECK: %[[BCAST_MASKLOAD:.+]] = vector.bitcast %[[SOURCE]] : vector<2xi8> to vector<8xi2>

// CHECK: %[[CST1:.+]] = arith.constant dense<false> : vector<8xi1>

// Create a mask vector 
// Note that if indices are known then we can fold the part generating mask.
// CHECK: %[[EX4:.+]] = vector.extract %[[MASK]][0] : i1 from vector<3xi1>
// CHECK: %[[IN4:.+]] = vector.insert %[[EX4]], %[[CST1]] [%[[LINEAR2]]] : i1 into vector<8xi1>
// CHECK: %[[EX5:.+]] = vector.extract %[[MASK]][1] : i1 from vector<3xi1>
// CHECK: %[[IN5:.+]] = vector.insert %[[EX5]], %[[IN4]] [%[[INCIDX]]] : i1 into vector<8xi1>
// CHECK: %[[EX6:.+]] = vector.extract %[[MASK]][2] : i1 from vector<3xi1>
// CHECK: %[[NEW_MASK:.+]] = vector.insert %[[EX6]], %[[IN5]] [%[[INCIDX2]]] : i1 into vector<8xi1>

// Select the effective part from the source and passthru vectors
// CHECK: %[[SELECT:.+]] = arith.select %[[NEW_MASK]], %[[BCAST_MASKLOAD]], %[[NEW_PASSTHRU]] : vector<8xi1>, vector<8xi2>

// Finally, insert the selected parts into actual passthru vector.
// CHECK: %[[EX7:.+]] = vector.extract %[[SELECT]][%[[LINEAR2]]] : i2 from vector<8xi2>
// CHECK: %[[IN7:.+]] = vector.insert %[[EX7]], %[[PTH]] [0] : i2 into vector<3xi2>
// CHECK: %[[EX8:.+]] = vector.extract %[[SELECT]][%[[INCIDX]]] : i2 from vector<8xi2>
// CHECK: %[[IN8:.+]] = vector.insert %[[EX8]], %[[IN7]] [1] : i2 into vector<3xi2>
// CHECK: %[[EX9:.+]] = vector.extract %[[SELECT]][%[[INCIDX2]]] : i2 from vector<8xi2>
// CHECK: %[[IN9:.+]] = vector.insert %[[EX9]], %[[IN8]] [2] : i2 into vector<3xi2>

// -----

func.func @vector_maskedload_i2_constant_mask_unaligned(%passthru: vector<5xi2>) -> vector<5xi2> {
  %0 = memref.alloc() : memref<3x5xi2>
  %mask = arith.constant dense<[false, true, true, true, false]> : vector<5xi1>
  %c0 = arith.constant 0 : index
  %c1 = arith.constant 1 : index
  %1 = vector.maskedload %0[%c1, %c0], %mask, %passthru :
    memref<3x5xi2>, vector<5xi1>, vector<5xi2> into vector<5xi2>
  return %1 : vector<5xi2>
}

// CHECK: func @vector_maskedload_i2_constant_mask_unaligned(
// CHECK-SAME: %[[PTH:.+]]: vector<5xi2>) -> vector<5xi2>
// CHECK: %[[ALLOC:.+]] = memref.alloc() : memref<4xi8>
// CHECK: %[[MASK:.+]] = arith.constant dense<[false, true, true, true, false]> : vector<5xi1>

// Emulated masked load from alloc:
// CHECK: %[[COMPRESSED_MASK:.+]] = arith.constant dense<true> : vector<2xi1>
// CHECK: %[[EMPTY:.+]] = arith.constant dense<0> : vector<8xi2>
// CHECK: %[[PTH_PADDED:.+]] = vector.insert_strided_slice %[[PTH]], %[[EMPTY]]
// CHECK-SAME: {offsets = [1], strides = [1]} : vector<5xi2> into vector<8xi2>
// CHECK: %[[PTH_PADDED_UPCAST:.+]] = vector.bitcast %[[PTH_PADDED]] : vector<8xi2> to vector<2xi8>
// CHECK: %[[C1:.+]] = arith.constant 1 : index
// CHECK: %[[MASKLOAD:.+]] = vector.maskedload %[[ALLOC]][%[[C1]]], %[[COMPRESSED_MASK]], %[[PTH_PADDED_UPCAST]]
// CHECK: %[[MASKLOAD_DOWNCAST:.+]] = vector.bitcast %[[MASKLOAD]] : vector<2xi8> to vector<8xi2>

// Select from emulated loaded vector and passthru vector:
// TODO: fold insert_strided_slice into source if possible.
// CHECK: %[[EMPTY_MASK:.+]] = arith.constant dense<false> : vector<8xi1>
// CHECK: %[[MASK_PADDED:.+]] = vector.insert_strided_slice %[[MASK]], %[[EMPTY_MASK]]
// CHECK-SAME: {offsets = [1], strides = [1]} : vector<5xi1> into vector<8xi1>
// CHECK: %[[SELECT:.+]] = arith.select %[[MASK_PADDED]], %[[MASKLOAD_DOWNCAST]], %[[PTH_PADDED]] : vector<8xi1>, vector<8xi2>
// CHECK: %[[RESULT:.+]] = vector.extract_strided_slice %[[SELECT]]
// CHECK-SAME: {offsets = [1], sizes = [5], strides = [1]} : vector<8xi2> to vector<5xi2>
// CHECK: return %[[RESULT]] : vector<5xi2>

///----------------------------------------------------------------------------------------
/// vector.store
///----------------------------------------------------------------------------------------

// -----

// Most basic example to demonstrate where partial stores are not needed.

func.func @vector_store_i2_const_index_no_partial_store(%arg0: vector<4xi2>) {
    %0 = memref.alloc() : memref<13xi2>
    %c4 = arith.constant 4 : index
    vector.store %arg0, %0[%c4] : memref<13xi2>, vector<4xi2>
    return
}
// CHECK-LABEL:   func.func @vector_store_i2_const_index_no_partial_store(
// CHECK-SAME:      %[[ARG_0:[0-9]+|[a-zA-Z$._-][a-zA-Z0-9$._-]*]]: vector<4xi2>) {
// CHECK-NOT:       memref.generic_atomic_rmw
// CHECK:           %[[ALLOC:.*]] = memref.alloc() : memref<4xi8>
// CHECK:           %[[UPCAST:.*]] = vector.bitcast %[[ARG_0]] : vector<4xi2> to vector<1xi8>
// CHECK:           %[[C1:.*]] = arith.constant 1 : index
// CHECK:           vector.store %[[UPCAST]], %[[ALLOC]]{{\[}}%[[C1]]] : memref<4xi8>, vector<1xi8>

// -----

// Small modification of the example above to demonstrate where partial stores
// are needed.

func.func @vector_store_i2_const_index_two_partial_stores(%arg0: vector<4xi2>) {
    %0 = memref.alloc() : memref<13xi2>
    %c3 = arith.constant 3 : index
    vector.store %arg0, %0[%c3] : memref<13xi2>, vector<4xi2>
    return
}

// CHECK-LABEL:   func.func @vector_store_i2_const_index_two_partial_stores(
// CHECK-SAME:      %[[ARG_0:[0-9]+|[a-zA-Z$._-][a-zA-Z0-9$._-]*]]: vector<4xi2>) {
// CHECK:           %[[VAL_1:.*]] = memref.alloc() : memref<4xi8>

// First atomic RMW:
// CHECK:           %[[IDX_1:.*]] = arith.constant 0 : index
// CHECK:           %[[MASK_1:.*]] = arith.constant dense<[false, false, false, true]> : vector<4xi1>
// CHECK:           %[[INIT:.*]] = arith.constant dense<0> : vector<4xi2>
// CHECK:           %[[SLICE_1:.*]] = vector.extract_strided_slice %[[ARG_0]] {offsets = [0], sizes = [1], strides = [1]} : vector<4xi2> to vector<1xi2>
// CHECK:           %[[V1:.*]] = vector.insert_strided_slice %[[SLICE_1]], %[[INIT]] {offsets = [3], strides = [1]} : vector<1xi2> into vector<4xi2>
// CHECK:           memref.generic_atomic_rmw %[[VAL_1]]{{\[}}%[[IDX_1]]] : memref<4xi8> {
// CHECK:           ^bb0(%[[VAL_8:.*]]: i8):
// CHECK:             %[[VAL_9:.*]] = vector.from_elements %[[VAL_8]] : vector<1xi8>
// CHECK:             %[[DOWNCAST_1:.*]] = vector.bitcast %[[VAL_9]] : vector<1xi8> to vector<4xi2>
// CHECK:             %[[SELECT_1:.*]] = arith.select %[[MASK_1]], %[[V1]], %[[DOWNCAST_1]] : vector<4xi1>, vector<4xi2>
// CHECK:             %[[UPCAST_1:.*]] = vector.bitcast %[[SELECT_1]] : vector<4xi2> to vector<1xi8>
// CHECK:             %[[RES_1:.*]] = vector.extract %[[UPCAST_1]][0] : i8 from vector<1xi8>
// CHECK:             memref.atomic_yield %[[RES_1]] : i8
// CHECK:           }

// Second atomic RMW:
// CHECK:           %[[VAL_14:.*]] = arith.constant 1 : index
// CHECK:           %[[IDX_2:.*]] = arith.addi %[[IDX_1]], %[[VAL_14]] : index
// CHECK:           %[[VAL_16:.*]] = vector.extract_strided_slice %[[ARG_0]] {offsets = [1], sizes = [3], strides = [1]} : vector<4xi2> to vector<3xi2>
// CHECK:           %[[V2:.*]] = vector.insert_strided_slice %[[VAL_16]], %[[INIT]] {offsets = [0], strides = [1]} : vector<3xi2> into vector<4xi2>
// CHECK:           %[[MASK_2:.*]] = arith.constant dense<[true, true, true, false]> : vector<4xi1>
// CHECK:            memref.generic_atomic_rmw %[[VAL_1]]{{\[}}%[[IDX_2]]] : memref<4xi8> {
// CHECK:           ^bb0(%[[VAL_20:.*]]: i8):
// CHECK:             %[[VAL_21:.*]] = vector.from_elements %[[VAL_20]] : vector<1xi8>
// CHECK:             %[[DONWCAST_2:.*]] = vector.bitcast %[[VAL_21]] : vector<1xi8> to vector<4xi2>
// CHECK:             %[[SELECT_2:.*]] = arith.select %[[MASK_2]], %[[V2]], %[[DONWCAST_2]] : vector<4xi1>, vector<4xi2>
// CHECK:             %[[UPCAST_2:.*]] = vector.bitcast %[[SELECT_2]] : vector<4xi2> to vector<1xi8>
// CHECK:             %[[RES_2:.*]] = vector.extract %[[UPCAST_2]][0] : i8 from vector<1xi8>
// CHECK:             memref.atomic_yield %[[RES_2]] : i8
// CHECK:           }

// -----

func.func @vector_store_i2_const_index_two_partial_stores(%arg0: vector<3xi2>) {
    %src = memref.alloc() : memref<3x3xi2>
    %c0 = arith.constant 0 : index
    %c2 = arith.constant 2 : index
    vector.store %arg0, %src[%c2, %c0] :memref<3x3xi2>, vector<3xi2>
    return
}

// Emit two atomic RMW partial stores. Store 6 bits from the input vector (bits [12:18)),
// into bytes [1:2] from a 3-byte output memref. Due to partial storing,
// both bytes are accessed partially through masking.

// CHECK-LABEL: func @vector_store_i2_const_index_two_partial_stores(
// CHECK-SAME: %[[ARG0:.+]]: vector<3xi2>)
// CHECK: %[[ALLOC:.+]] = memref.alloc() : memref<3xi8>
// CHECK: %[[C1:.+]] = arith.constant 1 : index
// CHECK: %[[CST:.+]] = arith.constant dense<[false, false, true, true]> : vector<4xi1>
// CHECK: %[[CST_0:.+]] = arith.constant dense<0> : vector<4xi2>

// Part 1 atomic RMW sequence (load bits [12, 16) from %src_as_bytes[1])
// CHECK: %[[EXTRACT:.+]] = vector.extract_strided_slice %[[ARG0]]
// CHECK-SAME: {offsets = [0], sizes = [2], strides = [1]} : vector<3xi2> to vector<2xi2>
// CHECK: %[[INSERT:.+]] = vector.insert_strided_slice %[[EXTRACT]], %[[CST_0]]
// CHECK-SAME: {offsets = [2], strides = [1]} : vector<2xi2> into vector<4xi2>
// CHECK: %[[ATOMIC_RMW:.+]] = memref.generic_atomic_rmw %[[ALLOC]][%[[C1]]] : memref<3xi8> {
// CHECK: %[[ARG:.+]]: i8):
// CHECK: %[[FROM_ELEM:.+]] = vector.from_elements %[[ARG]] : vector<1xi8>
// CHECK: %[[BITCAST:.+]] = vector.bitcast %[[FROM_ELEM]] : vector<1xi8> to vector<4xi2>
// CHECK: %[[SELECT:.+]] = arith.select %[[CST]], %[[INSERT]], %[[BITCAST]] : vector<4xi1>, vector<4xi2>
// CHECK: %[[BITCAST2:.+]] = vector.bitcast %[[SELECT]] : vector<4xi2> to vector<1xi8>
// CHECK: %[[EXTRACT2:.+]] = vector.extract %[[BITCAST2]][0] : i8 from vector<1xi8>
// CHECK: memref.atomic_yield %[[EXTRACT2]] : i8

// Part 2 atomic RMW sequence (load bits [16, 18) from %src_as_bytes[2])
// CHECK: %[[ADDR2:.+]] = arith.addi %[[C1]], %[[C1]] : index
// CHECK: %[[EXTRACT3:.+]] = vector.extract_strided_slice %[[ARG0]]
// CHECK-SAME: {offsets = [2], sizes = [1], strides = [1]} : vector<3xi2> to vector<1xi2>
// CHECK: %[[INSERT2:.+]] = vector.insert_strided_slice %[[EXTRACT3]], %[[CST_0]]
// CHECK-SAME: {offsets = [0], strides = [1]} : vector<1xi2> into vector<4xi2>
// CHECK: %[[CST1:.+]] = arith.constant dense<[true, false, false, false]> : vector<4xi1>
// CHECK: %[[ATOMIC_RMW2:.+]] = memref.generic_atomic_rmw %[[ALLOC]][%[[ADDR2]]] : memref<3xi8> {
// CHECK: %[[ARG2:.+]]: i8):
// CHECK: %[[FROM_ELEM2:.+]] = vector.from_elements %[[ARG2]] : vector<1xi8>
// CHECK: %[[BITCAST4:.+]] = vector.bitcast %[[FROM_ELEM2]] : vector<1xi8> to vector<4xi2>
// CHECK: %[[SELECT2:.+]] = arith.select %[[CST1]], %[[INSERT2]], %[[BITCAST4]] : vector<4xi1>, vector<4xi2>
// CHECK: %[[BITCAST5:.+]] = vector.bitcast %[[SELECT2]] : vector<4xi2> to vector<1xi8>
// CHECK: %[[EXTRACT4:.+]] = vector.extract %[[BITCAST5]][0] : i8 from vector<1xi8>
// CHECK: memref.atomic_yield %[[EXTRACT4]] : i8

// -----

func.func @vector_store_i2_two_partial_one_full_stores(%arg0: vector<7xi2>) {
    %0 = memref.alloc() : memref<3x7xi2>
    %c0 = arith.constant 0 : index
    %c1 = arith.constant 1 : index
    vector.store %arg0, %0[%c1, %c0] :memref<3x7xi2>, vector<7xi2>
    return
}

// In this example, emit 2 atomic RMWs and 1 non-atomic store:
// CHECK-LABEL: func @vector_store_i2_two_partial_one_full_stores(
// CHECK-SAME: %[[ARG0:.+]]: vector<7xi2>)
// CHECK: %[[ALLOC:.+]] = memref.alloc() : memref<6xi8>
// CHECK: %[[C1:.+]] = arith.constant 1 : index
// CHECK: %[[CST:.+]] = arith.constant dense<[false, false, false, true]> : vector<4xi1>
// CHECK: %[[CST0:.+]] = arith.constant dense<0> : vector<4xi2>

// First atomic RMW:
// CHECK: %[[EXTRACT:.+]] = vector.extract_strided_slice %[[ARG0]]
// CHECK-SAME: {offsets = [0], sizes = [1], strides = [1]} : vector<7xi2> to vector<1xi2>
// CHECK: %[[INSERT:.+]] = vector.insert_strided_slice %[[EXTRACT]], %[[CST0]]
// CHECK-SAME: {offsets = [3], strides = [1]} : vector<1xi2> into vector<4xi2>
// CHECK: %[[ATOMIC_RMW:.+]] = memref.generic_atomic_rmw %[[ALLOC]][%[[C1]]] : memref<6xi8> {
// CHECK: %[[ARG:.+]]: i8):
// CHECK: %[[FROM_ELEM:.+]] = vector.from_elements %[[ARG]] : vector<1xi8>
// CHECK: %[[BITCAST:.+]] = vector.bitcast %[[FROM_ELEM]] : vector<1xi8> to vector<4xi2>
// CHECK: %[[SELECT:.+]] = arith.select %[[CST]], %[[INSERT]], %[[BITCAST]] : vector<4xi1>, vector<4xi2>
// CHECK: %[[BITCAST2:.+]] = vector.bitcast %[[SELECT]] : vector<4xi2> to vector<1xi8>
// CHECK: %[[EXTRACT2:.+]] = vector.extract %[[BITCAST2]][0] : i8 from vector<1xi8>
// CHECK: memref.atomic_yield %[[EXTRACT2]] : i8

// Non-atomic store:
// CHECK: %[[ADDR:.+]] = arith.addi %[[C1]], %[[C1]] : index
// CHECK: %[[EXTRACT2:.+]] = vector.extract_strided_slice %[[ARG0]]
// CHECK-SAME: {offsets = [1], sizes = [4], strides = [1]} : vector<7xi2> to vector<4xi2>
// CHECK: %[[BITCAST3:.+]] = vector.bitcast %[[EXTRACT2]] : vector<4xi2> to vector<1xi8>
// CHECK: vector.store %[[BITCAST3]], %[[ALLOC]][%[[ADDR]]] : memref<6xi8>, vector<1xi8>

// Second atomic RMW:
// CHECK: %[[ADDR2:.+]] = arith.addi %[[ADDR]], %[[C1]] : index
// CHECK: %[[EXTRACT3:.+]] = vector.extract_strided_slice %[[ARG0]]
// CHECK-SAME: {offsets = [5], sizes = [2], strides = [1]} : vector<7xi2> to vector<2xi2>
// CHECK: %[[INSERT2:.+]] = vector.insert_strided_slice %[[EXTRACT3]], %[[CST0]]
// CHECK-SAME: {offsets = [0], strides = [1]} : vector<2xi2> into vector<4xi2>
// CHECK: %[[CST1:.+]] = arith.constant dense<[true, true, false, false]> : vector<4xi1> 
// CHECK: %[[ATOMIC_RMW2:.+]] = memref.generic_atomic_rmw %[[ALLOC]][%[[ADDR2]]] : memref<6xi8> {
// CHECK: %[[ARG2:.+]]: i8):
// CHECK: %[[FROM_ELEM2:.+]] = vector.from_elements %[[ARG2]] : vector<1xi8>
// CHECK: %[[BITCAST4:.+]] = vector.bitcast %[[FROM_ELEM2]] : vector<1xi8> to vector<4xi2>
// CHECK: %[[SELECT2:.+]] = arith.select %[[CST1]], %[[INSERT2]], %[[BITCAST4]] :
// CHECK-SAME: vector<4xi1>, vector<4xi2>
// CHECK: %[[BITCAST5:.+]] = vector.bitcast %[[SELECT2]] : vector<4xi2> to vector<1xi8>
// CHECK: %[[EXTRACT4:.+]] = vector.extract %[[BITCAST5]][0] : i8 from vector<1xi8>
// CHECK: memref.atomic_yield %[[EXTRACT4]] : i8    

// -----

func.func @vector_store_i2_const_index_one_partial_store(%arg0: vector<1xi2>) {
    %0 = memref.alloc() : memref<4x1xi2>
    %c0 = arith.constant 0 : index
    %c1 = arith.constant 1 : index
    vector.store %arg0, %0[%c1, %c0] : memref<4x1xi2>, vector<1xi2>
    return
}

// In this example, only emit 1 atomic store
// CHECK-LABEL: func @vector_store_i2_const_index_one_partial_store(
// CHECK-SAME: %[[ARG0:.+]]: vector<1xi2>)
// CHECK: %[[ALLOC:.+]] = memref.alloc() : memref<1xi8>
// CHECK: %[[C0:.+]] = arith.constant 0 : index
// CHECK: %[[CST:.+]] = arith.constant dense<[false, true, false, false]> : vector<4xi1>
// CHECK: %[[CST0:.+]] = arith.constant dense<0> : vector<4xi2>
// CHECK: %[[INSERT:.+]] = vector.insert_strided_slice %[[ARG0]], %[[CST0]]
// CHECK-SAME: {offsets = [1], strides = [1]} : vector<1xi2> into vector<4xi2>

// CHECK: %[[ATOMIC_RMW:.+]] = memref.generic_atomic_rmw %[[ALLOC]][%[[C0]]] : memref<1xi8> {
// CHECK: %[[ARG:.+]]: i8):
// CHECK: %[[FROM_ELEM:.+]] = vector.from_elements %[[ARG]] : vector<1xi8>
// CHECK: %[[BITCAST:.+]] = vector.bitcast %[[FROM_ELEM]] : vector<1xi8> to vector<4xi2>
// CHECK: %[[SELECT:.+]] = arith.select %[[CST]], %[[INSERT]], %[[BITCAST]] : vector<4xi1>, vector<4xi2>
// CHECK: %[[BITCAST2:.+]] = vector.bitcast %[[SELECT]] : vector<4xi2> to vector<1xi8>
// CHECK: %[[EXTRACT2:.+]] = vector.extract %[[BITCAST2]][0] : i8 from vector<1xi8>
// CHECK: memref.atomic_yield %[[EXTRACT2]] : i8
