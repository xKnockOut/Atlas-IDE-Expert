unit Cm.W1057c;

// W1057 Implicit string cast
// Erwartet: -
// Gegenfall zu string-conversion (#1377): Diese Umwandlungen übersetzt dcc ohne Meldung (noch mit dcc
// zu bestätigen); Atlas darf hier nichts melden.

interface

implementation

procedure Ausgeben(const AText: string); overload;
begin
end;

procedure Ausgeben(const AText: AnsiString); overload;
begin
end;

procedure Fall(var AText: string; const AAnsi: AnsiString; const ABreit: WideString; AZeichen: AnsiChar);
var
  mAnsi: AnsiString;
  mBreit: WideString;
  mOk: Boolean;
begin
  mAnsi := 'abc'; // <- ohne Meldung
  mAnsi := 'Preis ' + #$20AC; // <- ohne Meldung
  AText := ABreit; // <- ohne Meldung
  mBreit := AText; // <- ohne Meldung
  AText := string(AAnsi); // <- ohne Meldung (W1059 ist aus)
  mAnsi := AnsiString(AText); // <- ohne Meldung (W1060 ist aus)
  AText[1] := 'x'; // <- ohne Meldung (W1068 ist aus)
  mOk := AZeichen in ['a'..'z']; // <- ohne Meldung
  Ausgeben(AAnsi); // <- ohne Meldung
  {$WARN IMPLICIT_STRING_CAST OFF}
  AText := AAnsi; // <- ohne Meldung
  {$WARN IMPLICIT_STRING_CAST DEFAULT}
  if mOk then
    Ausgeben(mAnsi + mBreit);
end;

end.
