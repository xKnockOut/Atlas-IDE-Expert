unit Atlas.Text.Columns;

// Spalten einer Zeile, wie der Editor sie zeigt: Tabs springen zur nächsten Tabstelle, #13 zählt nicht. Gemeinsam
// für Klammerpaare, Unterstreichungen der Probleme, Hilfslinien, Platzhalter und Inline-Werte (#514, #615).

interface

type
  TTextColumns = record
  public
    /// <summary>Zeile wie im Editor: Tabs bis zur nächsten Tabstelle als Leerzeichen, ohne #13.</summary>
    class function DisplayLine(const ALine: string; ATabWidth: Integer): string; static;
    /// <summary>True, wenn der Textlauf ARun ab der 1-basierten Spalte AColumn in ADisplayLine steht.</summary>
    class function RunMatches(const ADisplayLine, ARun: string; AColumn: Integer): Boolean; static;
    /// <summary>Zeichenindex (0-basiert) in ALine als 1-basierte Editorspalte, Tabs aufgelöst.</summary>
    class function ColumnOf(const ALine: string; ACharacter, ATabWidth: Integer): Integer; static;
    /// <summary>Editorspalte (1-basiert) hinter den ersten ACharacter Zeichen von ALine wie in DisplayLine (#13
    /// zählt nicht, hinter dem Zeilenende keine Spalte mehr).</summary>
    class function DisplayColumn(const ALine: string; ACharacter, ATabWidth: Integer): Integer; static;
    /// <summary>Zeigt der Editor AEditorLine wie AModelLine? Tabs aufgelöst, Leerzeichen am Ende egal.</summary>
    class function SameDisplayLine(const AEditorLine, AModelLine: string; ATabWidth: Integer): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  System.Math;

class function TTextColumns.DisplayLine(const ALine: string; ATabWidth: Integer): string;
var
  mBuilder: TStringBuilder;
  mCh: Char;
begin
  mBuilder := TStringBuilder.Create;
  try
    for mCh in ALine do
    begin
      if (mCh = #9) and (ATabWidth > 0) then
      begin
        mBuilder.Append(' ', ATabWidth - mBuilder.Length mod ATabWidth);
      end
      else if mCh <> #13 then
      begin
        mBuilder.Append(mCh);
      end;
    end;
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
end;

class function TTextColumns.RunMatches(const ADisplayLine, ARun: string; AColumn: Integer): Boolean;
begin
  Result := (ARun <> '') and (AColumn >= 1) and (Copy(ADisplayLine, AColumn, Length(ARun)) = ARun);
end;

class function TTextColumns.ColumnOf(const ALine: string; ACharacter, ATabWidth: Integer): Integer;
var
  mIndex: Integer;
begin
  Result := 1;
  for mIndex := 1 to ACharacter do
  begin
    if (mIndex <= Length(ALine)) and (ALine[mIndex] = #9) and (ATabWidth > 0) then
    begin
      Result := ((Result - 1) div ATabWidth + 1) * ATabWidth + 1;
    end
    else
    begin
      Inc(Result);
    end;
  end;
end;

class function TTextColumns.DisplayColumn(const ALine: string; ACharacter, ATabWidth: Integer): Integer;
begin
  Result := Length(DisplayLine(Copy(ALine, 1, Max(0, ACharacter)), ATabWidth)) + 1;
end;

class function TTextColumns.SameDisplayLine(const AEditorLine, AModelLine: string; ATabWidth: Integer): Boolean;
begin
  Result := TrimRight(DisplayLine(AEditorLine, ATabWidth)) = TrimRight(DisplayLine(AModelLine, ATabWidth));
end;

end.
