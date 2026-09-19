const std = @import("std");
const log = std.log;
const Allocator = std.mem.Allocator;

const graphics = @import("graphics.zig");
const input = @import("input.zig");

const Inventory = @import("inventory.zig");

pub var currentWindow: Window = .empty;

pub const Window = struct
{
  const TextArea = struct
  {
    size: graphics.Coord,
    cursorPos: graphics.Coord,
    /// Data exists directly after this in memory
    data: [0]u8,

    pub fn at(self: *TextArea, pos: graphics.Coord) *u8
    {
      return &@as([*]u8, &self.data)[pos[1]*self.size[0] + pos[0]];   
    }

    /// Moves self.cursorPos by offset, wrapping at self.size
    pub fn moveCursor(self: *TextArea, offset: graphics.Offset) graphics.Coord
    {
      self.cursorPos =
        @intCast(@mod(@as(graphics.Offset, self.cursorPos)+offset, self.size));

      return self.cursorPos;
    }

    pub fn typeCh(self: *TextArea, ch: u8) void
    {
      self.at(self.cursorPos).* = ch;

      if (@reduce(.Or, self.cursorPos != self.size - graphics.Coord{1, 1}))
      {
        if (self.cursorPos[0] < self.size[0]-1)
        {
          self.cursorPos[0] += 1;
        } else
        {
          self.cursorPos[0] = 0;
          self.cursorPos[1] += 1;
        }
      }
    }
  };

  const Inputs = struct
  {
    cursorUp: []const u8,
    cursorDown: []const u8,
    cursorLeft: []const u8,
    cursorRight: []const u8,
    select: []const u8,
    back: []const u8,
  };

  const BorderStyle = struct
  {
    cornerCh: graphics.Char,
    rowCh: graphics.Char,
    colCh: graphics.Char,
  };

  pub const ElementIndex = u16;
  const Element = enum
  {
    Text,
    Inventory,
    TextArea,
  };
  const ElementPtr = union(Element)
  {
    Text: []const u8,
    Inventory: *Inventory,
    TextArea: *TextArea,
  };

  /// Pos is the coordinate of the top-left pixel inside the window's border
  pos: graphics.Coord,
  size: graphics.Coord,

  inputs: ?Inputs,
  cursorIndex: ElementIndex,
  /// This may need to be increased later, but currently I only need one bit of data
  cursorDepth: u1,

  border: BorderStyle,
  elements: []ElementPtr,

  dataBuffer: std.ArrayListAligned(u8, .fromByteUnits(@alignOf(ElementPtr))),

  pub const empty = Window{
    .pos = @splat(0),
    .size = @splat(0),
    .inputs = null,
    .cursorIndex = 0,
    .cursorDepth = 0,
    .border = .{.cornerCh = 0, .rowCh = 0, .colCh = 0},
    .elements = &.{},
    .dataBuffer = .empty,
  };

  pub const ElementArgument = union(Element)
  {
    Text: struct {string: []const u8},
    Inventory: *Inventory,
    TextArea: struct {
      size: graphics.Coord,
      /// Memory is freed by the updateContents function
      initialData: []const u8
    },
  };

  /// Replaces the current elements of the window with elements
  pub fn updateContents(
    self: *Window,
    allocator: Allocator,
    elements: []const ElementArgument) error{OutOfMemory, TooManyElements}!void
  {
    if (elements.len > std.math.maxInt(ElementIndex))
    {
      return error.TooManyElements;
    }

    try self.dataBuffer.ensureTotalCapacityPrecise(
      allocator, getDataBufferSize(elements)
    );
    self.dataBuffer.clearRetainingCapacity();

    self.elements = @ptrCast(@alignCast(
      self.dataBuffer.addManyAsSliceAssumeCapacity(
        elements.len * @sizeOf(ElementPtr)
      )
    ));
    self.size = @splat(0);

    for (elements, self.elements) |argElement, *resultElement|
    {
      switch (argElement)
      {
        .Text => |text|
        {
          resultElement.* = .{
            .Text = self.dataBuffer.unusedCapacitySlice()[0..text.string.len]
          };

          self.dataBuffer.appendSliceAssumeCapacity(text.string);

          self.size[0] = @truncate(@max(self.size[0], text.string.len));
          self.size[1] += 1;
        },
        .Inventory => |inventory|
        {
          resultElement.* = .{.Inventory = inventory};
          self.size[1] += @intCast(inventory.items.items.len);
        },
        .TextArea => |text|
        {
          resultElement.* = .{.TextArea = @ptrCast(@alignCast(
            self.dataBuffer.addManyAsSliceAssumeCapacity(@sizeOf(TextArea))
          ))};

          resultElement.TextArea.size = text.size;
          resultElement.TextArea.cursorPos = @splat(0);

          const textData = self.dataBuffer.addManyAsSliceAssumeCapacity(
            text.size[0] * text.size[1]
          );
          @memcpy(textData.ptr, text.initialData);
          @memset(textData[text.initialData.len..], ' ');

          if (text.initialData.len > 0) allocator.free(text.initialData);

          self.size[0] = @max(self.size[0], text.size[0]);
          self.size[1] += @intCast(text.size[1]);
        },
      }
    }
  }

  pub fn deinit(self: *Window, allocator: Allocator) void
  {
    self.dataBuffer.deinit(allocator);

    self.* = undefined;
  }

  pub fn isOpen(self: Window) bool
  {
    return @reduce(.And, self.size > graphics.Coord{0, 0});
  }

  pub fn close(self: *Window) void
  {
    self.size = @splat(0);
  }

  pub fn handleInputs(self: *Window) void
  {
    if (self.inputs == null)
    {
      return;
    }

    var rawInput: input.RawInput = undefined;
    //if (input.currentInput == null)
    //{
      rawInput = input.getInputRaw() orelse return;
    //}

    log.debug(
      "Window input ({}, \"{?s}\"), (cursor: {}, {})\n",
      .{rawInput.key, rawInput.event, self.cursorIndex, self.cursorDepth}
    );

    const keyCh = std.math.cast(u8, rawInput.key);
    if (
      self.cursorDepth == 1 and
      self.elements[self.cursorIndex] == .TextArea and
      keyCh != null and keyCh.? >= 32 and keyCh.? < 127)
    {
      const textArea = self.elements[self.cursorIndex].TextArea;

      textArea.typeCh(keyCh.?);
    } else if (rawInput.event) |event|
    {
      if (std.mem.eql(u8, self.inputs.?.cursorUp, event))
      {
        if (self.cursorDepth == 0)
        {
          self.cursorIndex = @intCast(@mod(
            @as(i17, self.cursorIndex)-1,
            @as(i17, @intCast(self.elements.len))
          ));
        } else if (self.cursorDepth == 1)
        {
          const textArea = self.elements[self.cursorIndex].TextArea;

          _ = textArea.moveCursor(.{0, -1});
        }
      } else if (std.mem.eql(u8, self.inputs.?.cursorDown, event))
      {
        if (self.cursorDepth == 0)
        {
          self.cursorIndex =
            (self.cursorIndex+1) % @as(u16, @intCast(self.elements.len));
        } else if (self.cursorDepth == 1)
        {
          const textArea = self.elements[self.cursorIndex].TextArea;

          _ = textArea.moveCursor(.{0, 1});
        }
      } else if (std.mem.eql(u8, self.inputs.?.cursorLeft, event))
      {
        if (self.cursorDepth == 0)
        {
          // TODO: this
        } else if (self.cursorDepth == 1)
        {
          const textArea = self.elements[self.cursorIndex].TextArea;

          _ = textArea.moveCursor(.{-1, 0});
        }
      } else if (std.mem.eql(u8, self.inputs.?.cursorRight, event))
      {
        if (self.cursorDepth == 0)
        {
          // TODO: this
        } else if (self.cursorDepth == 1)
        {
          const textArea = self.elements[self.cursorIndex].TextArea;

          _ = textArea.moveCursor(.{1, 0});
        }
      } else if (std.mem.eql(u8, self.inputs.?.select, event))
      {
        if (self.cursorDepth == 0)
        {
          self.cursorDepth = 1;
        }
      } else if (std.mem.eql(u8, self.inputs.?.back, event))
      {
        if (self.cursorDepth == 1)
        {
          self.cursorDepth = 0;
        } else if (self.cursorDepth == 0)
        {
          self.close();
        }
      }
    }
  }

  pub fn draw(self: Window) graphics.Error!void
  {
    const farCorner = self.pos + self.size;

    try graphics.drawCh(
      .{@as(i16, self.pos[0])-1, @as(i16, self.pos[1])-1}, self.border.cornerCh
    );
    try graphics.drawCh(
      .{farCorner[0]           , @as(i16, self.pos[1])-1}, self.border.cornerCh
    );
    try graphics.drawCh(
      .{farCorner[0]           , farCorner[1]           }, self.border.cornerCh
    );
    try graphics.drawCh(
      .{@as(i16, self.pos[0])-1, farCorner[1]           }, self.border.cornerCh
    );

    for (self.pos[0]..farCorner[0]) |x|
    {
      try graphics.drawCh(
        .{@intCast(x), @as(i16, self.pos[1])-1}, self.border.rowCh
      );
      try graphics.drawCh(.{@intCast(x), farCorner[1]}, self.border.rowCh);
    }

    for (self.pos[1]..farCorner[1]) |y|
    {
      try graphics.drawCh(
        .{@as(i16, self.pos[0])-1, @intCast(y)}, self.border.colCh
      );
      try graphics.drawCh(.{farCorner[0], @intCast(y)}, self.border.colCh);
    }

    var yVal = self.pos[1];
    for (0.., self.elements) |e, element| switch (element)
    {
      .Text => |text|
      {
        if (self.cursorIndex == e)
        {
          try graphics.drawCh(.{self.pos[0], yVal}, '_');
        }

        try graphics.drawStr(.{self.pos[0], yVal}, text);
        yVal += 1;
      },
      .TextArea => |text|
      {
        if (self.cursorIndex == e)
        {
          const elementPos = graphics.Coord{self.pos[0], yVal};
          if (self.cursorDepth == 0)
          {
            try graphics.drawCh(elementPos, '_');
          } else if (self.cursorDepth == 1)
          {
            try graphics.drawCh(elementPos + text.cursorPos, '_');
          }
        }

        for (0..text.size[1]) |textY|
        {
          const row: [*]u8 = @ptrCast(text.at(.{0, @intCast(textY)}));

          try graphics.drawStr(.{self.pos[0], yVal}, row[0..text.size[0]]);

          yVal += 1;
        }
      },
      else =>
      {
        log.err(
          "Draw for window element \"{s}\", not implemented\n",
          .{@tagName(element)}
        );
      }
    };
  }

  fn getDataBufferSize(elements: []const ElementArgument) usize
  {
    var result: usize = elements.len * @sizeOf(ElementPtr);

    for (elements) |element|
    {
      result += switch (element)
      {
        .Text => |text| text.string.len,
        .Inventory => 0,
        .TextArea => |text| @sizeOf(TextArea) + text.size[0]*text.size[1]
      };
    }

    return result;
  }
};
