unit Atlas.Common.Editing.SuggestionContext;

// Wissen aus dem Index für Schattentext-Vorschläge eines KI-Anbieters (#1922):
// Zu einer Zeile im Rumpf einer Methode liefert Declarations die Köpfe der
// Klasse und ihrer Mitglieder (Felder, Properties, Methoden) als eine Zeile je
// Deklaration, damit der Anbieter vorhandene Namen statt erfundener nennt.
// - ClassAt sucht von der Zeile aufwärts den Kopf der umgebenden Routine
//   ("procedure TFoo.Bar", auch "class function", "constructor") bis zum
//   Abschnitt implementation; eingerückte Routinen ohne Klasse gelten als
//   verschachtelt. Ohne Klassennamen gibt es nichts.
// - Mitglieder kommen aus der Unit der Datei im Index, sonst aus der Unit, die
//   die Klasse deklariert. Höchstens cMaxDeclarations Zeilen.
// Reine Funktionen über Text und Index-Einträgen, threadsicher.

interface

uses
  Atlas.Common.Index.Contract;

type
  TSuggestionContext = class
  public const
    /// <summary>Höchstzahl der Zeilen in Declarations.</summary>
    cMaxDeclarations = 60;
  public
    /// <summary>Klasse der Methode, in deren Rumpf die Zeile ALine (0-basiert) von AText steht; '' außerhalb.
    /// </summary>
    class function ClassAt(const AText: string; ALine: Integer): string; static;
    /// <summary>Kopf der Klasse AClass und ihrer Mitglieder aus AUnit, je eine Zeile in der Reihenfolge der
    /// Deklaration.</summary>
    class function MembersOf(const AUnit: TUnitIndex; const AClass: string): TArray<string>; static;
    /// <summary>Köpfe für die Zeile ALine von AText in AFileName: aus der Unit der Datei, sonst aus der Unit,
    /// die die Klasse deklariert; nil ohne Klasse oder Index.</summary>
    class function Declarations(const AIndex: ISymbolIndex; const AFileName, AText: string;
      ALine: Integer): TArray<string>; static;
  end;

implementation

uses
  System.SysUtils,
  System.Math,
  System.Character;

/// <summary>Erstes Wort von ALine (ohne Einrückung) klein; '' ohne Buchstaben am Anfang.</summary>
function FirstWord(const ALine: string; out ARest: string): string;
var
  mText: string;
  mEnd: Integer;
begin
  mText := TrimLeft(ALine);
  mEnd := 1;
  while (mEnd <= Length(mText)) and (mText[mEnd].IsLetterOrDigit or (mText[mEnd] = '_')) do
  begin
    Inc(mEnd);
  end;
  Result := LowerCase(Copy(mText, 1, mEnd - 1));
  ARest := TrimLeft(Copy(mText, mEnd, MaxInt));
end;

/// <summary>Qualifizierter Name am Anfang von ARest ("TFoo.Bar(…") → "TFoo"; '' ohne Punkt.</summary>
function OwnerOf(const ARest: string): string;
var
  mEnd: Integer;
  mName: string;
begin
  mEnd := 1;
  while (mEnd <= Length(ARest)) and (ARest[mEnd].IsLetterOrDigit or CharInSet(ARest[mEnd], ['_', '.'])) do
  begin
    Inc(mEnd);
  end;
  mName := Copy(ARest, 1, mEnd - 1);
  Result := '';
  if mName.LastIndexOf('.') > 0 then
  begin
    Result := Copy(mName, 1, mName.LastIndexOf('.'));
  end;
end;

function IsRoutineWord(const AWord: string): Boolean;
begin
  Result := (AWord = 'procedure') or (AWord = 'function') or (AWord = 'constructor') or (AWord = 'destructor') or
    (AWord = 'operator');
end;

{ TSuggestionContext }

class function TSuggestionContext.ClassAt(const AText: string; ALine: Integer): string;
var
  mLines: TArray<string>;
  mIndex: Integer;
  mWord, mRest: string;
begin
  Result := '';
  mLines := AText.Split([#13#10, #10]);
  for mIndex := Min(ALine, High(mLines)) downto 0 do
  begin
    mWord := FirstWord(mLines[mIndex], mRest);
    if mWord = 'implementation' then
    begin
      Exit;
    end;
    if mWord = 'class' then
    begin
      mWord := FirstWord(mRest, mRest);
    end;
    if IsRoutineWord(mWord) then
    begin
      Result := OwnerOf(mRest);
      // Eingerückte Routine ohne Klasse ist verschachtelt: weiter aufwärts zur äußeren. Am Zeilenanfang ist sie
      // selbst die äußere.
      if (Result <> '') or not mLines[mIndex].StartsWith(' ') then
      begin
        Exit;
      end;
    end;
  end;
end;

class function TSuggestionContext.MembersOf(const AUnit: TUnitIndex; const AClass: string): TArray<string>;
var
  mSymbol: TIndexSymbol;
  mOwner, mMembers: TArray<string>;
begin
  mOwner := nil;
  mMembers := nil;
  for mSymbol in AUnit.Symbols do
  begin
    if (mSymbol.Container = '') and SameText(mSymbol.Name, AClass) and (mSymbol.Signature <> '') then
    begin
      mOwner := [mSymbol.Signature];
    end
    else if SameText(mSymbol.Container, AClass) and (mSymbol.Signature <> '') and
      (Length(mMembers) < cMaxDeclarations - 1) then
    begin
      mMembers := mMembers + [mSymbol.Signature];
    end;
  end;
  Result := mOwner + mMembers;
end;

class function TSuggestionContext.Declarations(const AIndex: ISymbolIndex; const AFileName, AText: string;
  ALine: Integer): TArray<string>;
var
  mClass: string;
  mUnit: TUnitIndex;
  mLocation: TSymbolLocation;
begin
  Result := nil;
  mClass := ClassAt(AText, ALine);
  if (mClass = '') or (AIndex = nil) then
  begin
    Exit;
  end;
  if AIndex.FindFile(AFileName, mUnit) then
  begin
    Result := MembersOf(mUnit, mClass);
  end;
  if Length(Result) > 0 then
  begin
    Exit;
  end;
  for mLocation in AIndex.FindSymbols(mClass) do
  begin
    if (mLocation.Symbol.Container = '') and AIndex.FindFile(mLocation.FileName, mUnit) then
    begin
      Result := MembersOf(mUnit, mClass);
      if Length(Result) > 0 then
      begin
        Exit;
      end;
    end;
  end;
end;

end.
