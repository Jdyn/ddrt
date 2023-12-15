defmodule DDRT.Debug do
  @moduledoc false

  import IO.ANSI

  require Logger

  def log(:insertion_success, %{id: id, path: path}) do
    Logger.debug(
      cyan() <>
        "[" <>
        green() <>
        "Insertion" <>
        cyan() <>
        "] success: " <>
        yellow() <>
        "[#{id}]" <> cyan() <> " was inserted at" <> yellow() <> " ['#{hd(path)}']"
    )
  end

  def log(:insertion_speed, %{time: time}) do
    cyan() <>
      "[" <> green() <> "Insertion" <> cyan() <> "] took" <> yellow() <> " #{time} µs"
  end

  def log(:insertion_key_exists, %{id: id }) do
    Logger.debug(
      cyan() <>
        "[" <>
        green() <>
        "Insertion" <>
        cyan() <>
        "] failed:" <>
        yellow() <>
        " [#{id}] " <>
        cyan() <>
        "already exists at tree." <>
        yellow() <> " [Tip]" <> cyan() <> " use " <> yellow() <> "update_leaf/3"
    )
  end
end
