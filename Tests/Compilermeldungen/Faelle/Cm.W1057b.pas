unit Cm.W1057b;

// W1057 Implicit string cast
// Erwartet: W1057
// Zweiter Versuch (#1377): RawByteString und UTF8String nach string, string nach UTF8String,
// AnsiString nach WideString, Argument an einen const-Parameter und Inline-Variable.

interface

implementation

procedure Ausgeben(const AText: string);
begin
end;

procedure Fall(const ARoh: RawByteString; const AUtf8: UTF8String; const AAnsi: AnsiString; const AText: string);
var
  mText: string;
  mUtf8: UTF8String;
  mBreit: WideString;
begin
  mText := ARoh; // <- W1057
  mText := AUtf8; // <- W1057
  mUtf8 := AText; // <- W1057
  mBreit := AAnsi; // <- W1057
  Ausgeben(AAnsi); // <- W1057
  var mNeu: string := AAnsi; // <- W1057
  Ausgeben(mText + mUtf8 + mBreit + mNeu);
end;

end.
