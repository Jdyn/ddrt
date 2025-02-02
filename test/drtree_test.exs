defmodule DynamicRtreeTest do
  use ExUnit.Case
  alias DDRT.DynamicRtree
  alias DDRT.DynamicRtreeImpl.Utils
  alias DDRT.DynamicRtreeImpl.BoundingBoxGenerator

  setup_all do
    DynamicRtree.start_link(conf: [])
    {:ok, %{}}
  end

  describe "[DynamicRtree creation]" do
    test "always returns {:ok,map()}" do
      {:ok, t} = DynamicRtree.new()
      assert DynamicRtree.new() |> is_tuple()
      assert t |> is_map()
    end

    test "raise badMapError with not map opts keyword list" do
      assert_raise FunctionClauseError, fn -> DynamicRtree.new(1) end
      assert_raise FunctionClauseError, fn -> DynamicRtree.new(:map) end
      assert_raise FunctionClauseError, fn -> DynamicRtree.new("pokemon") end
    end
  end

  describe "[DynamicRtree actions]" do
    test "Map insert and bulk insert works as expected" do
      DynamicRtree.new()
      new_tuple = {new_node, _new_box} = {UUID.uuid1(), [{1, 2}, {3, 4}]}
      {:ok, t} = DynamicRtree.insert(new_tuple)
      assert t == DynamicRtree.tree()
      {:key_exists, t2} = DynamicRtree.insert(new_tuple)
      assert t2 == t
      {cont, parent, box} = t[new_node]
      assert cont == :leaf
      assert parent == t[:root]
      assert box == [{1, 2}, {3, 4}]

      DynamicRtree.new()

      {:ok, t} =
        DynamicRtree.insert([
          {0, [{4, 5}, {6, 7}]},
          {1, [{-34, -33}, {40, 41}]},
          {2, [{-50, -49}, {15, 16}]},
          {3, [{33, 34}, {-10, -9}]},
          {4, [{35, 36}, {-9, -8}]},
          {5, [{0, 1}, {-9, -8}]},
          {6, [{9, 10}, {9, 10}]}
        ])

      assert t == DynamicRtree.tree()

      root = t[:root]
      {ch, _root_ptr, root_box} = t[root]
      assert t |> Enum.to_list() |> length == t |> Enum.uniq() |> length
      assert length(ch) == 2
      assert root_box == [{-50, 36}, {-10, 41}]
    end

    test "MerkleMap insert and bulk insert works as expected" do
      DynamicRtree.new(type: MerkleMap)
      new_tuple = {new_node, _new_box} = {UUID.uuid1(), [{1, 2}, {3, 4}]}
      {:ok, t} = DynamicRtree.insert(new_tuple)
      assert t == DynamicRtree.tree()
      {cont, parent, box} = t |> MerkleMap.get(new_node)
      assert cont == :leaf
      assert parent == t[:root]
      assert box == [{1, 2}, {3, 4}]

      DynamicRtree.new(type: MerkleMap)

      {:ok, t} =
        DynamicRtree.insert([
          {0, [{4, 5}, {6, 7}]},
          {1, [{-34, -33}, {40, 41}]},
          {2, [{-50, -49}, {15, 16}]},
          {3, [{33, 34}, {-10, -9}]},
          {4, [{35, 36}, {-9, -8}]},
          {5, [{0, 1}, {-9, -8}]},
          {6, [{9, 10}, {9, 10}]}
        ])

      assert t == DynamicRtree.tree()

      root = t |> MerkleMap.get(:root)
      {ch, _root_ptr, root_box} = t |> MerkleMap.get(root)
      assert t |> Enum.to_list() |> length == t |> Enum.uniq() |> length
      assert length(ch) == 2
      assert root_box == [{-50, 36}, {-10, 41}]
    end

    test "MerkleMap inserts a triangular bounding box without crash" do
      DynamicRtree.new(type: MerkleMap)

      {:ok, t} = DynamicRtree.insert({1, [{9, 9}, {9, 9.1}]})

      assert t == DynamicRtree.tree()

      root = t |> MerkleMap.get(:root)
      {ch, _root_ptr, root_box} = t |> MerkleMap.get(root)
      assert t |> Enum.to_list() |> length == t |> Enum.uniq() |> length
      assert length(ch) == 1
      assert root_box == [{9, 9}, {9, 9.1}]
    end

    test "insert returns error and old tree if key already exists" do
      DynamicRtree.new(type: MerkleMap)

      same_key = UUID.uuid1()

      first_tuple = {same_key, [{1, 2}, {3, 4}]}

      {:ok, first_tree} = DynamicRtree.insert(first_tuple)

      second_tuple = {same_key, [{3, 4}, {5, 6}]}

      # Assert the insert returns the correct result
      assert {:key_exists, _} = DynamicRtree.insert(second_tuple)

      {:key_exists, second_tree} = DynamicRtree.insert(second_tuple)

      # Assert the tree was unchanged by the failed insert
      assert first_tree == second_tree
    end

    test "upsert inserts or updates new or existing key" do
      DynamicRtree.new(type: MerkleMap)

      same_key = UUID.uuid1()

      first_tuple = {same_key, [{1, 2}, {3, 4}]}

      {:ok, old_tree} = DynamicRtree.upsert(first_tuple)

      second_tuple = {same_key, [{3, 4}, {5, 6}]}

      # Assert the insert returns the correct result
      assert {:ok, new_tree} = DynamicRtree.upsert(second_tuple)

      # Assert that the tuple with id key has been updated
      {:leaf, id, bbox} = MerkleMap.get(new_tree, same_key)

      assert bbox == [{3, 4}, {5, 6}]

      assert old_tree != new_tree
    end

    test "Map delete leaf keeps tree consistency" do
      DynamicRtree.new()

      data =
        BoundingBoxGenerator.generate(100, 1, [])
        |> Enum.with_index()
        |> Enum.map(fn {x, i} -> {i, x} end)

      {:ok, t} = DynamicRtree.insert(data)
      delete_id = 90
      old_parent = t[delete_id] |> elem(1)
      old_parent_childs = t[old_parent] |> elem(0)

      assert t |> Map.has_key?(delete_id)
      refute t[delete_id] == nil
      assert delete_id in old_parent_childs

      {:ok, t} = DynamicRtree.delete(delete_id)
      assert t == DynamicRtree.tree()

      refute t |> Map.has_key?(delete_id)
      assert t[delete_id] == nil
      refute delete_id in (t[old_parent] |> elem(0))

      {:ok, same_t} = DynamicRtree.delete(delete_id)
      assert ^t = same_t

      {:ok, t} = DynamicRtree.delete(1..100 |> Enum.map(fn x -> x end))
      root = t[:root]
      {ch, _parent, root_box} = t[root]
      {_ch, _parent, leaf_box} = t[0]
      assert length(ch) == 1
      assert leaf_box == root_box
      {:ok, t} = DynamicRtree.delete(0)
      assert length(t[root] |> elem(0)) == 0
      {_ch, _parent, root_box} = t[root]
      assert root_box == [{0, 0}, {0, 0}]
    end

    test "MerkleMap delete leaf keeps tree consistency" do
      DynamicRtree.new(type: MerkleMap)

      data =
        BoundingBoxGenerator.generate(100, 1, [])
        |> Enum.with_index()
        |> Enum.map(fn {x, i} -> {i, x} end)

      {:ok, t} = DynamicRtree.insert(data)
      delete_id = 90
      old_parent = t |> MerkleMap.get(delete_id) |> elem(1)
      old_parent_childs = t |> MerkleMap.get(old_parent) |> elem(0)

      assert t |> MerkleMap.has_key?(delete_id)
      refute t[delete_id] == nil
      assert delete_id in old_parent_childs

      {:ok, t} = DynamicRtree.delete(delete_id)
      assert t == DynamicRtree.tree()

      refute t |> MerkleMap.has_key?(delete_id)
      assert t |> MerkleMap.get(delete_id) == nil
      refute delete_id in (t |> MerkleMap.get(old_parent) |> elem(0))

      {:ok, same_t} = DynamicRtree.delete(delete_id)
      assert ^t = same_t

      {:ok, t} = DynamicRtree.delete(1..100 |> Enum.map(fn x -> x end))
      root = t |> MerkleMap.get(:root)
      {ch, _parent, root_box} = t |> MerkleMap.get(root)
      {_ch, _parent, leaf_box} = t |> MerkleMap.get(0)
      assert length(ch) == 1
      assert leaf_box == root_box
      {:ok, t} = DynamicRtree.delete(0)
      assert length(t[root] |> elem(0)) == 0
      {_ch, _parent, root_box} = t |> MerkleMap.get(root)
      assert root_box == [{0, 0}, {0, 0}]
    end

    test "Map queries return good stuff" do
      DynamicRtree.new()

      DynamicRtree.insert([
        {0, [{4, 5}, {6, 7}]},
        {1, [{-34, -33}, {40, 41}]},
        {2, [{-50, -49}, {15, 16}]},
        {3, [{33, 34}, {-10, -9}]},
        {4, [{35, 36}, {-9, -8}]},
        {5, [{0, 1}, {-9, -8}]},
        {6, [{9, 10}, {9, 10}]}
      ])

      assert DynamicRtree.query([{4, 5}, {6, 7}]) == {:ok, [0]}
      assert DynamicRtree.query([{2, 5}, {1, 6.1}]) == {:ok, [0]}
      assert DynamicRtree.query([{-60, 0}, {0, 100}]) |> elem(1) |> Enum.sort() == [1, 2]

      assert DynamicRtree.query([{-100, 100}, {-100, 100}]) |> elem(1) |> Enum.sort() == [
               0,
               1,
               2,
               3,
               4,
               5,
               6
             ]

      assert DynamicRtree.query([{1, 2}, {1, 2}]) == {:ok, []}
      assert DynamicRtree.query([{0, 0}, {0, 0}]) == {:ok, []}
      assert DynamicRtree.pquery([{4, 5}, {6, 7}], 0) == {:ok, [33_762_080_631_324_007]}
      assert DynamicRtree.pquery([{4, 5}, {6, 7}], 1) == {:ok, [101_671_470_050_757_358]}
      assert DynamicRtree.pquery([{4, 5}, {6, 7}], 2) == {:ok, [0]}
      assert DynamicRtree.pquery([{4, 5}, {6, 7}], 1000) == {:ok, [0]}
      assert DynamicRtree.pquery([{44, 45}, {-7, 6}], 0) == {:ok, []}
      assert DynamicRtree.pquery([{44, 45}, {-7, 6}], 1) == {:ok, []}
      assert DynamicRtree.pquery([{44, 45}, {-7, 6}], 2) == {:ok, []}

      DynamicRtree.new()
      assert DynamicRtree.query([{4, 5}, {6, 7}]) == {:ok, []}
      assert DynamicRtree.query([{-60, 0}, {0, 100}]) == {:ok, []}
      assert DynamicRtree.query([{-100, 100}, {-100, 100}]) == {:ok, []}
      assert DynamicRtree.query([{1, 2}, {1, 2}]) == {:ok, []}
      assert DynamicRtree.query([{0, 0}, {0, 0}]) == {:ok, []}
    end

    test "MerkleMap queries return good stuff" do
      DynamicRtree.new(type: MerkleMap)

      DynamicRtree.insert([
        {0, [{4, 5}, {6, 7}]},
        {1, [{-34, -33}, {40, 41}]},
        {2, [{-50, -49}, {15, 16}]},
        {3, [{33, 34}, {-10, -9}]},
        {4, [{35, 36}, {-9, -8}]},
        {5, [{0, 1}, {-9, -8}]},
        {6, [{9, 10}, {9, 10}]}
      ])

      assert DynamicRtree.query([{4, 5}, {6, 7}]) == {:ok, [0]}
      assert DynamicRtree.query([{2, 5}, {1, 6.1}]) == {:ok, [0]}
      assert DynamicRtree.query([{-60, 0}, {0, 100}]) |> elem(1) |> Enum.sort() == [1, 2]

      assert DynamicRtree.query([{-100, 100}, {-100, 100}]) |> elem(1) |> Enum.sort() == [
               0,
               1,
               2,
               3,
               4,
               5,
               6
             ]

      assert DynamicRtree.query([{1, 2}, {1, 2}]) == {:ok, []}
      assert DynamicRtree.query([{0, 0}, {0, 0}]) == {:ok, []}
      assert DynamicRtree.pquery([{4, 5}, {6, 7}], 0) == {:ok, [33_762_080_631_324_007]}
      assert DynamicRtree.pquery([{4, 5}, {6, 7}], 1) == {:ok, [101_671_470_050_757_358]}
      assert DynamicRtree.pquery([{4, 5}, {6, 7}], 2) == {:ok, [0]}
      assert DynamicRtree.pquery([{4, 5}, {6, 7}], 1000) == {:ok, [0]}
      assert DynamicRtree.pquery([{44, 45}, {-7, 6}], 0) == {:ok, []}
      assert DynamicRtree.pquery([{44, 45}, {-7, 6}], 1) == {:ok, []}
      assert DynamicRtree.pquery([{44, 45}, {-7, 6}], 2) == {:ok, []}

      DynamicRtree.new(type: MerkleMap)
      assert DynamicRtree.query([{4, 5}, {6, 7}]) == {:ok, []}
      assert DynamicRtree.query([{-60, 0}, {0, 100}]) == {:ok, []}
      assert DynamicRtree.query([{-100, 100}, {-100, 100}]) == {:ok, []}
      assert DynamicRtree.query([{1, 2}, {1, 2}]) == {:ok, []}
      assert DynamicRtree.query([{0, 0}, {0, 0}]) == {:ok, []}
    end

    test "Map update and bulk update works" do
      DynamicRtree.new()
      {:ok, t} = DynamicRtree.update(0, [{13, 14}, {6, 7}])
      assert t == DynamicRtree.tree()

      {:ok, t} =
        DynamicRtree.insert([
          {0, [{4, 5}, {6, 7}]},
          {1, [{-34, -33}, {40, 41}]},
          {2, [{-50, -49}, {15, 16}]},
          {3, [{33, 34}, {-10, -9}]},
          {4, [{35, 36}, {-9, -8}]},
          {5, [{0, 1}, {-9, -8}]},
          {6, [{9, 10}, {9, 10}]}
        ])

      root = t[:root]
      {_ch, _dad, root_box} = t[root]
      {_ch, _dad, leaf_box} = t[2]
      assert root_box == [{-50, 36}, {-10, 41}]
      assert leaf_box == [{-50, -49}, {15, 16}]

      {:leaf, p, _box} = t[0]
      {:ok, t} = DynamicRtree.update(0, [{13, 14}, {6, 7}])
      assert p == t[0] |> elem(1)
      assert t[0] |> elem(2) == [{13, 14}, {6, 7}]

      {:leaf, p, _box} = t[0]
      {:ok, t} = DynamicRtree.update(5, [{-1, 0}, {-8, -7}])
      assert p == t[0] |> elem(1)
      assert t[5] |> elem(2) == [{-1, 0}, {-8, -7}]

      {:leaf, p, _box} = t[0]
      {:ok, t} = DynamicRtree.update(0, [{-5, -4}, {6, 7}])
      refute p == t[0] |> elem(1)
      assert t[0] |> elem(2) == [{-5, -4}, {6, 7}]

      {:ok, t} =
        DynamicRtree.bulk_update([
          {0, [{4, 5}, {6, 7}]},
          {1, [{-34, -33}, {40, 41}]},
          {2, [{-50, -49}, {15, 16}]},
          {3, [{33, 34}, {-10, -9}]},
          {4, [{35, 36}, {-9, -8}]},
          {5, [{0, 1}, {-9, -8}]},
          {6, [{9, 10}, {9, 10}]}
        ])

      assert t[0] |> elem(2) == [{4, 5}, {6, 7}]
      assert t[1] |> elem(2) == [{-34, -33}, {40, 41}]
      assert t[2] |> elem(2) == [{-50, -49}, {15, 16}]
      assert t[3] |> elem(2) == [{33, 34}, {-10, -9}]
      assert t[4] |> elem(2) == [{35, 36}, {-9, -8}]
      assert t[5] |> elem(2) == [{0, 1}, {-9, -8}]
      assert t[6] |> elem(2) == [{9, 10}, {9, 10}]
    end

    test "MerkleMap update and bulk update works" do
      DynamicRtree.new(type: MerkleMap)
      {:ok, t} = DynamicRtree.update(0, [{13, 14}, {6, 7}])
      assert t == DynamicRtree.tree()

      {:ok, t} =
        DynamicRtree.insert([
          {0, [{4, 5}, {6, 7}]},
          {1, [{-34, -33}, {40, 41}]},
          {2, [{-50, -49}, {15, 16}]},
          {3, [{33, 34}, {-10, -9}]},
          {4, [{35, 36}, {-9, -8}]},
          {5, [{0, 1}, {-9, -8}]},
          {6, [{9, 10}, {9, 10}]}
        ])

      root = t |> MerkleMap.get(:root)
      {_ch, _dad, root_box} = t |> MerkleMap.get(root)
      {_ch, _dad, leaf_box} = t |> MerkleMap.get(2)
      assert root_box == [{-50, 36}, {-10, 41}]
      assert leaf_box == [{-50, -49}, {15, 16}]

      {:leaf, p, _box} = t |> MerkleMap.get(0)
      {:ok, t} = DynamicRtree.update(0, [{13, 14}, {6, 7}])
      assert p == t |> MerkleMap.get(0) |> elem(1)
      assert t |> MerkleMap.get(0) |> elem(2) == [{13, 14}, {6, 7}]

      {:leaf, p, _box} = t |> MerkleMap.get(0)
      {:ok, t} = DynamicRtree.update(5, [{-1, 0}, {-8, -7}])
      assert p == t |> MerkleMap.get(0) |> elem(1)
      assert t |> MerkleMap.get(5) |> elem(2) == [{-1, 0}, {-8, -7}]

      {:leaf, p, _box} = t |> MerkleMap.get(0)
      {:ok, t} = DynamicRtree.update(0, [{-5, -4}, {6, 7}])
      refute p == t |> MerkleMap.get(0) |> elem(1)
      assert t |> MerkleMap.get(0) |> elem(2) == [{-5, -4}, {6, 7}]

      {:ok, t} =
        DynamicRtree.bulk_update([
          {0, [{4, 5}, {6, 7}]},
          {1, [{-34, -33}, {40, 41}]},
          {2, [{-50, -49}, {15, 16}]},
          {3, [{33, 34}, {-10, -9}]},
          {4, [{35, 36}, {-9, -8}]},
          {5, [{0, 1}, {-9, -8}]},
          {6, [{9, 10}, {9, 10}]}
        ])

      assert t |> MerkleMap.get(0) |> elem(2) == [{4, 5}, {6, 7}]
      assert t |> MerkleMap.get(1) |> elem(2) == [{-34, -33}, {40, 41}]
      assert t |> MerkleMap.get(2) |> elem(2) == [{-50, -49}, {15, 16}]
      assert t |> MerkleMap.get(3) |> elem(2) == [{33, 34}, {-10, -9}]
      assert t |> MerkleMap.get(4) |> elem(2) == [{35, 36}, {-9, -8}]
      assert t |> MerkleMap.get(5) |> elem(2) == [{0, 1}, {-9, -8}]
      assert t |> MerkleMap.get(6) |> elem(2) == [{9, 10}, {9, 10}]
    end
  end

  describe "[DynamicRtree geometry operations]" do
    test "combination of bounding boxes" do
      assert Utils.combine([{3, 19}, {-4, 20}], [{-5, 6}, {-4, 11}]) == [{-5, 19}, {-4, 20}]

      assert Utils.combine_multiple([[{3, 19}, {-4, 20}], [{5, 6}, {-4, 11}], [{0, 0}, {0, 0}]]) ==
               [{3, 19}, {-4, 20}]
    end

    test "overlapping of bounding boxes" do
      refute Utils.overlap?([{0, 0}, {0, 1}], [{1, 2}, {-1, 5}])
      assert Utils.overlap?([{1, 2}, {0, 1}], [{1, 2}, {-1, 5}])
      refute Utils.overlap?([{10, 12}, {10, 11}], [{1, 2}, {-1, 5}])
      assert Utils.overlap?([{0, 10}, {0, 10}], [{0, 5}, {0, 5}])

      assert Utils.overlap_area([{0, 0}, {0, 1}], [{1, 2}, {-1, 5}]) == 0
      assert Utils.overlap_area([{1, 2}, {0, 1}], [{1, 2}, {-1, 5}]) == 100
      assert Utils.overlap_area([{10, 12}, {10, 11}], [{1, 2}, {-1, 5}]) == 0
      assert Utils.overlap_area([{0, 10}, {0, 10}], [{0, 5}, {0, 5}]) == 25

      refute Utils.contained?([{0, 0}, {0, 1}], [{1, 2}, {-1, 5}])
      refute Utils.contained?([{1, 2}, {0, 1}], [{1, 2}, {-1, 5}])
      refute Utils.contained?([{10, 12}, {10, 11}], [{1, 2}, {-1, 5}])
      assert Utils.contained?([{0, 10}, {0, 10}], [{0, 5}, {0, 5}])
      assert Utils.contained?([{0, 10}, {0, 10}], [{0, 0}, {0, 0}])

      assert Utils.in_border?([{0, 10}, {0, 10}], [{0, 5}, {0, 5}])
      refute Utils.in_border?([{10, 12}, {10, 11}], [{1, 2}, {-1, 5}])
      refute Utils.in_border?([{0, 10}, {0, 10}], [{2, 5}, {2, 5}])
    end

    test "area operations" do
      assert Utils.enlargement_area([{10, 12}, {10, 11}], [{1, 2}, {-1, 5}]) == 130
      assert Utils.enlargement_area([{0, 10}, {0, 10}], [{2, 5}, {2, 5}]) == 0
      assert Utils.enlargement_area([{0, 10}, {0, 10}], [{0, 5}, {0, 5}]) == 0

      assert Utils.area([{0, 0}, {0, 0}]) == -1
      assert Utils.area([{0, 1}, {0, 1}]) == 1
      assert Utils.area([{-1, 0}, {0, 1}]) == 1
      assert Utils.area([{-10, 0}, {0, 1}]) == 10

      assert Utils.middle_value([{10, 12}, {10, 11}]) == 43 / 2

      assert Utils.get_posxy([{10, 12}, {10, 11}]) == %{x: 11, y: 10.5}

      assert Utils.box_move([{10, 12}, {10, 11}], x: 1, y: -1) == [{11, 13}, {9, 10}]
    end
  end
end
