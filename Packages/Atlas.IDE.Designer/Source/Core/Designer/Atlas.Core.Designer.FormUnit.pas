unit Atlas.Core.Designer.FormUnit;

// Unit eines Formulars als Zeilen, ohne VCL und Windows, für die Designer-
// Funktionen, die Felder und Handler im Text suchen (In Frame auslagern #611,
// Ereignis-Karte #612). Erwartet die Form, die die IDE schreibt: Klasse
// „TfrmKunden = class(TForm)“ bis „end;“, Methoden im Implementierungsteil
// ab Spalte 1 mit „procedure TfrmKunden.X(“.

interface

type
  TAtlasFormUnit = record
    Lines: TArray<string>;
    /// <summary>Zeilen aus AText (CRLF oder LF).</summary>
    class function Create(const AText: string): TAtlasFormUnit; static;
    /// <summary>Zeilen mit CRLF verbunden.</summary>
    function Text: string;
    /// <summary>Zeile „implementation“; ohne sie Length(Lines).</summary>
    function ImplementationLine: Integer;
    /// <summary>Zeilen der Klassendeklaration AFormClass: von „= class“ bis „end;“.</summary>
    function FindClass(const AFormClass: string; out AFirst, ALast: Integer): Boolean;
    /// <summary>Zeilen der Methode AFormClass.AName im Implementierungsteil ohne Leerzeilen am Ende.</summary>
    function FindBody(const AFormClass, AName: string; out AFirst, ALast: Integer): Boolean;
    /// <summary>Feld „edtName: TEdit;“ bzw. Methode „procedure X(...);“: Name; sonst ''.</summary>
    class function MemberName(const ALine: string; out AIsMethod: Boolean): string; static;
    /// <summary>Beginnt hier etwas Neues auf oberster Ebene (Methode, Abschnitt, „{ TKlasse }“)?</summary>
    class function IsMethodHeader(const ALine: string): Boolean; static;
    /// <summary>Anzahl führender Leerzeichen.</summary>
    class function SpacesOf(const ALine: string): Integer; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils;

const
  cCrLf = #13#10;

{ TAtlasFormUnit }

class function TAtlasFormUnit.Create(const AText: string): TAtlasFormUnit;
begin
  Result.Lines := AText.Replace(cCrLf, #10).Split([#10]);
end;

function TAtlasFormUnit.Text: string;
begin
  Result := string.Join(cCrLf, Lines);
end;

function TAtlasFormUnit.ImplementationLine: Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(Lines) do
  begin
    if SameText(Lines[mIndex].Trim, 'implementation') then
    begin
      Exit(mIndex);
    end;
  end;
  Result := Length(Lines);
end;

class function TAtlasFormUnit.SpacesOf(const ALine: string): Integer;
begin
  Result := 0;
  while (Result < Length(ALine)) and (ALine[Result + 1] = ' ') do
  begin
    Inc(Result);
  end;
end;

class function TAtlasFormUnit.IsMethodHeader(const ALine: string): Boolean;
var
  mText: string;
begin
  mText := ALine.TrimLeft;
  Result := (SpacesOf(ALine) = 0) and (StartsText('procedure ', mText) or StartsText('function ', mText) or
    StartsText('constructor ', mText) or StartsText('destructor ', mText) or StartsText('class ', mText) or
    SameText(mText.Trim, 'initialization') or SameText(mText.Trim, 'finalization') or SameText(mText.Trim, 'end.') or
    StartsText('{ T', mText));
end;

function TAtlasFormUnit.FindBody(const AFormClass, AName: string; out AFirst, ALast: Integer): Boolean;
var
  mIndex: Integer;
  mHead: string;
begin
  AFirst := -1;
  ALast := -1;
  mHead := 'procedure ' + AFormClass + '.' + AName;
  for mIndex := ImplementationLine to High(Lines) do
  begin
    if AFirst < 0 then
    begin
      if StartsText(mHead + '(', Lines[mIndex].Trim) or SameText(mHead + ';', Lines[mIndex].Trim) then
      begin
        AFirst := mIndex;
      end;
    end
    else if IsMethodHeader(Lines[mIndex]) then
    begin
      Break;
    end
    else
    begin
      ALast := mIndex;
    end;
  end;
  // Leerzeilen am Ende gehören nicht zur Methode.
  while (ALast > AFirst) and (Lines[ALast].Trim = '') do
  begin
    Dec(ALast);
  end;
  Result := (AFirst >= 0) and (ALast > AFirst);
end;

function TAtlasFormUnit.FindClass(const AFormClass: string; out AFirst, ALast: Integer): Boolean;
var
  mIndex: Integer;
begin
  AFirst := -1;
  ALast := -1;
  for mIndex := 0 to ImplementationLine - 1 do
  begin
    if (AFirst < 0) and StartsText(AFormClass + ' = class', Lines[mIndex].Trim) then
    begin
      AFirst := mIndex;
    end
    else if (AFirst >= 0) and SameText(Lines[mIndex].Trim, 'end;') then
    begin
      ALast := mIndex;
      Break;
    end;
  end;
  Result := (AFirst >= 0) and (ALast > AFirst);
end;

class function TAtlasFormUnit.MemberName(const ALine: string; out AIsMethod: Boolean): string;
var
  mText: string;
begin
  mText := ALine.Trim;
  AIsMethod := StartsText('procedure ', mText);
  if AIsMethod then
  begin
    mText := Copy(mText, Length('procedure ') + 1, MaxInt);
    Result := Copy(mText, 1, Pos('(', mText + '(') - 1).Replace(';', '').Trim;
  end
  else if (Pos(':', mText) > 0) and EndsText(';', mText) then
  begin
    Result := Copy(mText, 1, Pos(':', mText) - 1).Trim;
  end
  else
  begin
    Result := '';
  end;
end;

end.
