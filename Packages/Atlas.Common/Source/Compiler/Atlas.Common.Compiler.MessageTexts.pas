unit Atlas.Common.Compiler.MessageTexts;

// Aufbau der Meldungstexte von dcc (deutsche und englische Ausgabe): Namen stehen in Hochkommas.

interface

type
  TCompilerMessageTexts = record
    /// <summary>Namen in Hochkommas aus dem Meldungstext, in Reihenfolge; ein offenes Hochkomma am Ende zählt
    /// nicht.</summary>
    class function QuotedNames(const AText: string): TArray<string>; static;
  end;

implementation

{ TCompilerMessageTexts }

class function TCompilerMessageTexts.QuotedNames(const AText: string): TArray<string>;
var
  mIndex, mStart: Integer;
begin
  Result := nil;
  mIndex := 1;
  while mIndex <= Length(AText) do
  begin
    if AText[mIndex] = '''' then
    begin
      mStart := mIndex + 1;
      mIndex := mStart;
      while (mIndex <= Length(AText)) and (AText[mIndex] <> '''') do
      begin
        Inc(mIndex);
      end;
      if mIndex > Length(AText) then
      begin
        Break;
      end;
      Result := Result + [Copy(AText, mStart, mIndex - mStart)];
    end;
    Inc(mIndex);
  end;
end;

end.
