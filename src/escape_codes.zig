const esc: u8 = '\x1B';

const csi: [2]u8 = .{esc, '['};

pub const sgrIndexes = enum(u8) {
  Reset = 0,
  Bold = 1,
  Dim = 2,
  Italic = 3,
  Underline = 4,
  SlowBlink = 5,
  FastBlink = 6,
  InvertColors = 7,
  Hide = 8,
  Strikethrough = 9,
  MainFont = 10,
  AltFont1 = 11,
  AltFont2 = 12,
  AltFont3 = 13,
  AltFont4 = 14,
  AltFont5 = 15,
  AltFont6 = 16,
  AltFont7 = 17,
  AltFont8 = 18,
  AltFont9 = 19,
//20 Fraktur (Gothic) Rarely supported
  DoubleUnderline = 21,
  ResetBrightness = 22,
  ResetItalic = 23,
  ResetUnderline = 24,
  NoBlink = 25,
//26 Proportional spacing ITU T.61 and T.416, not known to be used on terminals
  ResetInvertedColors = 27,
  ResetHide = 28,
  ResetStrikethrough = 29,

  SetFGBlack = 30,
  SetFGRed = 31,
  SetFGGreen = 32,
  SetFGYellow = 33,
  SetFGBlue = 34,
  SetFGMagenta = 35,
  SetFGCyan = 36,
  SetFGWhite = 37,
  SetFGRGB = 38,
  ResetFGColor = 39,

  SetBGBlack = 40,
  SetBGRed = 41,
  SetBGGreen = 42,
  SetBGYellow = 43,
  SetBGBlue = 44,
  SetBGMagenta = 45,
  SetBGCyan = 46,
  SetBGWhite = 47,
  SetBGRGB = 48,

  ResetBGColor = 49,
//50 Disable proportional spacing T.61 and T.416
//51 Framed Implemented as "emoji variation selector" in mintty.[33]
//52 Encircled
  Overline = 53,
//54 Neither framed nor encircled
  ResetOverline = 55,
  SetULColorRGB = 58,
  ResetULColor = 59,
//60 Ideogram underline or right side line Rarely supported
//61 Ideogram double underline, or double line on the right side
//62 Ideogram overline or left side line
//63 Ideogram double overline, or double line on the left side
//64 Ideogram stress marking
//65 No ideogram attributes Reset the effects of all of 60–64
  Superscript = 73,
  Subscript = 74,
  ResetSuperSubScript = 75,

  SetFGLightBlack = 90,
  SetFGLightRed = 91,
  SetFGLightGreen = 92,
  SetFGLightYellow = 93,
  SetFGLightBlue = 94,
  SetFGLightMagenta = 95,
  SetFGLightCyan = 96,
  SetFGLightWhite = 97,

  SetBGLightBlack = 100,
  SetBGLightRed = 101,
  SetBGLightGreen = 102,
  SetBGLightYellow = 103,
  SetBGLightBlue = 104,
  SetBGLightMagenta = 105,
  SetBGLightCyan = 106,
  SetBGLightWhite = 107,
};

fn basicCSI(opcode: u8, amount: u16) [csi.len+5+1]u8
{
  var result: [csi.len+5+1]u8 = csi ++ "\x00\x00\x00\x00\x00\x00".*;
  var pos: u8 = csi.len;

  var counter: u16 = 10000;
  while (counter > 0)
  {
    if (amount/counter > 0)
    {
      const charOffset: u8 = @intCast((amount%(counter*10))/counter);
      result[pos] = '0' + charOffset;
      pos += 1;
    }

    counter /= 10;
  }

  result[pos] = opcode;

  return result;
}

/// Select graphic rendition - returns control string for the requested graphical modifier
pub fn sgr(attributeIndex: sgrIndexes) [csi.len+5+1]u8
{
  return basicCSI('m', @intFromEnum(attributeIndex));
}

pub fn moveCursorUp(amount: u16) [csi.len+5+1]u8
{
  return basicCSI('A', amount);
}

pub fn moveCursorDown(amount: u16) [csi.len+5+1]u8
{
  return basicCSI('B', amount);
}

pub fn moveCursorRight(amount: u16) [csi.len+5+1]u8
{
  return basicCSI('C', amount);
}

pub fn moveCursorLeft(amount: u16) [csi.len+5+1]u8
{
  return basicCSI('D', amount);
}

pub fn cursorDownLines(amount: u16) [csi.len+5+1]u8
{
  return basicCSI('E', amount);
}

pub fn cursorUpLines(amount: u16) [csi.len+5+1]u8
{
  return basicCSI('F', amount);
}

pub fn setCursorXPos(amount: u16) [csi.len+5+1]u8
{
  return basicCSI('G', amount);
}

pub fn cls() [csi.len+5+1]u8
{
  return basicCSI('J', 2);
}

pub fn setCursorPos(x: u16, y: u16) [csi.len+(6*2)]u8
{
  var result: [csi.len+(6*2)]u8 = csi ++ "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00".*;
  var pos: u8 = csi.len;

  var counter: u16 = 10000;
  while (counter > 0)
  {
    if (y/counter > 0)
    {
      result[pos] = '0' + (y%(counter*10))/counter;
      pos += 1;
    }

    counter /= 10;
  }

  result[pos] = ';';
  pos += 1;

  counter = 10000;
  while (counter > 0)
  {
    if (x/counter > 0)
    {
      result[pos] = '0' + (x%(counter*10))/counter;
      pos += 1;
    }

    counter /= 10;
  }

  result[pos] = 'H';

  return result;
}

fn changeCharSize(commandCode: u8) [csi.len+1]u8
{
  var result: [csi.len+1]u8 = .{esc, '#', '\x00'};

  result[2] = commandCode;

  return result;
}

pub fn doubleCharHeightTop() [csi.len+1]u8
{
  return changeCharSize('3');
}

pub fn doubleCharHeightBottom() [csi.len+1]u8
{
  return changeCharSize('4');
}

pub fn singleCharWidth() [csi.len+1]u8
{
  return changeCharSize('5');
}

pub fn doubleCharWidth() [csi.len+1]u8
{
  return changeCharSize('6');
}

pub fn setCursorVisible(visible: bool) [csi.len+4]u8
{
  var result: [csi.len+4]u8 = csi ++ "?25\x00".*;

  if (visible)
  {
    result[5] = 'h';
  } else
  {
    result[5] = 'l';
  }

  return result;
}
