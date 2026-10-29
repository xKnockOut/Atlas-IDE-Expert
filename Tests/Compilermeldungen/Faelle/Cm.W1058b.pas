unit Cm.W1058b;

// W1058 Implicit string cast with potential data loss
// Erwartet: W1058
// Zweiter Versuch (#1377): string nach RawByteString, WideString nach AnsiString, Argument an einen
// Wertparameter und Inline-Variable.

interface

implementation

procedure Ablegen(AText: AnsiString);
begin
end;

procedure Fall(const AText: string; const ABreit: WideString);
var
  mRoh: RawByteString;
  mAnsi: AnsiString;
begin
  mRoh := AText; // <- W1058
  mAnsi := ABreit; // <- W1058
  Ablegen(AText); // <- W1058
  var mNeu: AnsiString := AText; // <- W1058
  Ablegen(mRoh + mAnsi + mNeu);
end;

end.
