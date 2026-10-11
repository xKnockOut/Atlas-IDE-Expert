unit Atlas.Core.Files.TextDiff;

// Zeilenvergleich zweier Texte für „Vergleichen“ im Sammeldialog (#536):
// gleicher Anfang und gleiches Ende fallen weg; bei gleicher Zeilenzahl nur die
// geänderten Zeilen, sonst der geänderte Block. Zeilen mit Nummer im alten
// Text, "- " alt, "+ " neu.

interface

uses
  System.SysUtils;

type
  TAtlasTextDiff = class
  public const
    MaxLines = 400;
  public
    /// <summary>Unterschied von AOld (z. B. Puffer) zu ANew (z. B. Platte); leer, wenn gleich.</summary>
    class function Lines(const AOld, ANew: string): TArray<string>; static;
  end;

implementation

class function TAtlasTextDiff.Lines(const AOld, ANew: string): TArray<string>;
var
  OldLines, NewLines: TArray<string>;
  Prefix, Suffix, Index: Integer;

  procedure Add(const AText: string);
  begin
    if Length(Result) < MaxLines then
      Result := Result + [AText]
    else if Length(Result) = MaxLines then
      Result := Result + ['…'];
  end;

begin
  Result := nil;
  OldLines := AOld.Replace(#13#10, #10).Split([#10]);
  NewLines := ANew.Replace(#13#10, #10).Split([#10]);
  Prefix := 0;
  while (Prefix < Length(OldLines)) and (Prefix < Length(NewLines)) and (OldLines[Prefix] = NewLines[Prefix]) do
    Inc(Prefix);
  if (Prefix = Length(OldLines)) and (Prefix = Length(NewLines)) then
    Exit;
  Suffix := 0;
  while (Suffix < Length(OldLines) - Prefix) and (Suffix < Length(NewLines) - Prefix) and
    (OldLines[High(OldLines) - Suffix] = NewLines[High(NewLines) - Suffix]) do
    Inc(Suffix);
  if Length(OldLines) = Length(NewLines) then
  begin
    for Index := Prefix to High(OldLines) - Suffix do
      if OldLines[Index] <> NewLines[Index] then
      begin
        Add(Format('Zeile %d:', [Index + 1]));
        Add('- ' + OldLines[Index]);
        Add('+ ' + NewLines[Index]);
      end;
    Exit;
  end;
  Add(Format('ab Zeile %d:', [Prefix + 1]));
  for Index := Prefix to High(OldLines) - Suffix do
    Add('- ' + OldLines[Index]);
  for Index := Prefix to High(NewLines) - Suffix do
    Add('+ ' + NewLines[Index]);
end;

end.
