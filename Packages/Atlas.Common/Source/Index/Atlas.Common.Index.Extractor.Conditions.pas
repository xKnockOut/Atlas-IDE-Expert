unit Atlas.Common.Index.Extractor.Conditions;

// Bedingte Kompilierung für den Symbolindex: inaktive Zweige durch Leerzeichen ersetzen (Zeilen und Spalten
// bleiben) und Deklarationen aus nicht geltenden Zweigen als Unavailable erfassen (#476). Ausgelagert aus
// Atlas.Common.Index.Extractor.

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Preprocessor,
  Atlas.Common.Index.Contract;

type
  TIndexConditions = class
  public
    /// <summary>Ersetzt inaktive Zweige durch Leerzeichen; Zeilen und Spalten bleiben erhalten. Mit AResolver
    /// werden $I-Dateien gelesen, AIncludes erhält sie; AConditionals erhält die bedingten Zweige der
    /// Hauptdatei (#476).</summary>
    class function BlankInactive(const AText, AFileName: string; const ADefines: TArray<string>;
      const AResolver: TIncludeResolver; out AIncludes: TArray<string>;
      out AConditionals: TArray<TConditionalRange>): string; static;
    /// <summary>Bedingungen an die Symbole schreiben und Deklarationen aus nicht geltenden Zweigen
    /// als Unavailable erfassen (#476).</summary>
    class procedure AnnotateConditions(var AUnit: TUnitIndex; const AText: string;
      const AConditionals: TArray<TConditionalRange>); static;
    /// <summary>Liegt APosition in ARange (Ende ausgeschlossen)?</summary>
    class function InRange(const APosition: TTextPosition; const ARange: TTextRange): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Math,
  System.RegularExpressions,
  System.Generics.Collections,
  Atlas.Text.Lines;

const
  RoutinePattern = '^(procedure|function)\s+([A-Za-z_]\w*)\s*[(:;]';

type
  /// <summary>Sucht Deklarationen in nicht geltenden Zweigen einer Datei (#476).</summary>
  TConditionAnnotator = class
  private
    FSymbols: TArray<TIndexSymbol>;
    FLines: TArray<string>;
    // Abschnitt (type/const/var …) am Anfang jeder Zeile; einmal für die ganze Datei bestimmt.
    FSections: TArray<string>;
    FImplementationLine: Integer;
    FKnown: TDictionary<string, Boolean>;
    FUnavailable: TList<TIndexSymbol>;
    procedure ReadSections;
    procedure AddUnavailable(const AName: string; AKind: TIndexSymbolKind; ALine, AColumn: Integer;
      const ACondition, AContainer: string);
    /// <summary>Innerster Klassen-, Record- oder Interface-Typ, in dessen Rumpf ALine liegt; '' = keiner.</summary>
    function OwnerOf(ALine: Integer): string;
    function SectionAt(ALine: Integer): string;
    function LastLine(const AConditional: TConditionalRange): Integer;
    function AddRoutine(const ACode: string; ALine: Integer; const ACondition: string): Boolean;
    function AddMethodMember(const ACode: string; ALine: Integer; const AOwner, ACondition: string): Boolean;
    function AddPropertyMember(const ACode: string; ALine: Integer; const AOwner, ACondition: string): Boolean;
    procedure AddFieldMembers(const ACode: string; ALine: Integer; const AOwner, ACondition: string);
    procedure AddNamed(const ACode, APattern: string; AKind: TIndexSymbolKind; ALine: Integer;
      const ACondition: string);
    procedure AddTypeDeclaration(const ACode: string; ALine: Integer; const ACondition: string);
    procedure AddDeclaration(const ACode, ASection: string; ALine: Integer; const ACondition: string);
    procedure ScanRoutines(const AConditional: TConditionalRange);
    procedure ScanMembers(const AConditional: TConditionalRange; const AOwner: string);
    procedure ScanDeclarationLine(ALine: Integer; const ACondition: string; var ASection: string);
    procedure ScanDeclarations(const AConditional: TConditionalRange);
  public
    constructor Create(const ASymbols: TArray<TIndexSymbol>; const ALines: TArray<string>);
    destructor Destroy; override;
    procedure Scan(const AConditional: TConditionalRange);
    function Unavailable: TArray<TIndexSymbol>;
  end;

/// <summary>Schlüssel für Known: Mitglieder je Typ, denn gleichnamige Mitglieder anderer Typen sind etwas anderes.
/// </summary>
function QualifiedKey(const AName, AContainer: string): string;
begin
  Result := UpperCase(AName);
  if AContainer <> '' then
  begin
    Result := UpperCase(AContainer) + '.' + Result;
  end;
end;

/// <summary>Zeile ohne Zeilenkommentar.</summary>
function WithoutComment(const AText: string): string;
begin
  Result := AText;
  if Pos('//', Result) > 0 then
  begin
    Result := Copy(Result, 1, Pos('//', Result) - 1);
  end;
end;

/// <summary>Schlüsselwort am Zeilenanfang (type, const, var, threadvar, resourcestring, implementation,
/// interface) klein; '' ohne.</summary>
function SectionKeywordOf(const AText: string): string;
var
  mLine: string;
  mMatch: TMatch;
begin
  Result := '';
  mLine := TrimLeft(AText);
  if (mLine = '') or not CharInSet(mLine[1], ['a'..'z', 'A'..'Z']) then
  begin
    Exit;
  end;
  mMatch := TRegEx.Match(mLine, '^(type|const|var|threadvar|resourcestring|implementation|interface)\b',
    [roIgnoreCase]);
  if mMatch.Success then
  begin
    Result := LowerCase(mMatch.Groups[1].Value);
  end;
end;

/// <summary>Art eines Typs nach dem Wort hinter "=" (class, record, interface, "(" …).</summary>
function TypeKindOf(const AKeyword: string): TIndexSymbolKind;
begin
  if AKeyword = 'class' then
  begin
    Result := TIndexSymbolKind.ClassType;
  end
  else if AKeyword = 'record' then
  begin
    Result := TIndexSymbolKind.RecordType;
  end
  else if (AKeyword = 'interface') or (AKeyword = 'dispinterface') then
  begin
    Result := TIndexSymbolKind.InterfaceType;
  end
  else if AKeyword = '(' then
  begin
    Result := TIndexSymbolKind.EnumType;
  end
  else
  begin
    Result := TIndexSymbolKind.TypeAlias;
  end;
end;

/// <summary>Liegt ALine im Rumpf des Klassen-, Record- oder Interface-Typs ASymbol aus der Hauptdatei?</summary>
function IsBodyAround(const ASymbol: TIndexSymbol; ALine: Integer): Boolean;
begin
  Result := (ASymbol.Kind in [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType, TIndexSymbolKind.RecordType,
    TIndexSymbolKind.InterfaceType, TIndexSymbolKind.HelperType]) and (ASymbol.FileName = '') and
    (ASymbol.Range.StartPos.Line < ALine) and (ASymbol.Range.EndPos.Line >= ALine);
end;

/// <summary>Innerster geltender Zweig um APosition; -1 ohne.</summary>
function BestConditional(const APosition: TTextPosition; const AConditionals: TArray<TConditionalRange>): Integer;
var
  mIndex: Integer;
begin
  Result := -1;
  for mIndex := 0 to High(AConditionals) do
  begin
    if AConditionals[mIndex].Active and TIndexConditions.InRange(APosition, AConditionals[mIndex].Range) and
      ((Result < 0) or TIndexConditions.InRange(AConditionals[mIndex].Range.StartPos,
      AConditionals[Result].Range)) then
    begin
      Result := mIndex;
    end;
  end;
end;

/// <summary>Bedingung eines Symbols an APosition: der innerste geltende Zweig, sonst 'platform' bei der
/// Direktive an der Deklaration (erste Zeile), sonst ''.</summary>
function ConditionOf(const APosition: TTextPosition; const ALines: TArray<string>;
  const AConditionals: TArray<TConditionalRange>): string;
var
  mBest: Integer;
begin
  Result := '';
  mBest := BestConditional(APosition, AConditionals);
  if mBest >= 0 then
  begin
    Result := AConditionals[mBest].Condition;
  end
  else if (APosition.Line >= 0) and (APosition.Line <= High(ALines)) and
    TRegEx.IsMatch(ALines[APosition.Line], '\bplatform\s*;', [roIgnoreCase]) then
  begin
    Result := 'platform';
  end;
end;

/// <summary>Geltende Zweige: der innerste umgebende Zweig bestimmt die Bedingung.</summary>
procedure MarkActiveConditions(var AUnit: TUnitIndex; const ALines: TArray<string>;
  const AConditionals: TArray<TConditionalRange>);
var
  mIndex: Integer;
  mCondition: string;
begin
  for mIndex := 0 to High(AUnit.Symbols) do
  begin
    if AUnit.Symbols[mIndex].FileName = '' then
    begin
      mCondition := ConditionOf(AUnit.Symbols[mIndex].SelectionRange.StartPos, ALines, AConditionals);
      if mCondition <> '' then
      begin
        AUnit.Symbols[mIndex].Condition := mCondition;
      end;
    end;
  end;
end;

function HasInactive(const AConditionals: TArray<TConditionalRange>): Boolean;
var
  mConditional: TConditionalRange;
begin
  Result := False;
  for mConditional in AConditionals do
  begin
    if not mConditional.Active then
    begin
      Exit(True);
    end;
  end;
end;

/// <summary>Anfänge der Zeilen von AText (1-basiert).</summary>
function LineStartsOf(const AText: string): TList<Integer>;
var
  mIndex: Integer;
begin
  Result := TList<Integer>.Create;
  Result.Add(1);
  mIndex := 1;
  while mIndex <= Length(AText) do
  begin
    if (AText[mIndex] = #13) and (mIndex < Length(AText)) and (AText[mIndex + 1] = #10) then
    begin
      Inc(mIndex);
    end;
    if CharInSet(AText[mIndex], [#10, #13]) then
    begin
      Result.Add(mIndex + 1);
    end;
    Inc(mIndex);
  end;
end;

/// <summary>Offset (1-basiert) von APosition; über das Textende hinaus wird abgeschnitten.</summary>
function OffsetOf(ALineStarts: TList<Integer>; const APosition: TTextPosition; ATextLength: Integer): Integer;
begin
  if APosition.Line >= ALineStarts.Count then
  begin
    Exit(ATextLength + 1);
  end;
  Result := Min(ALineStarts[APosition.Line] + APosition.Character, ATextLength + 1);
end;

/// <summary>Zeichen AStart..AEnd-1 von AText durch Leerzeichen ersetzen, Zeilenumbrüche bleiben.</summary>
procedure BlankRange(var AText: string; AStart, AEnd: Integer);
var
  mIndex: Integer;
begin
  for mIndex := Max(AStart, 1) to Min(AEnd - 1, Length(AText)) do
  begin
    if not CharInSet(AText[mIndex], [#10, #13]) then
    begin
      AText[mIndex] := ' ';
    end;
  end;
end;

/// <summary>Inaktive Bereiche der Hauptdatei in AText durch Leerzeichen ersetzen.</summary>
procedure BlankRanges(var AText: string; const ARanges: TArray<TInactiveRange>);
var
  mLineStarts: TList<Integer>;
  mRange: TInactiveRange;
  mLength: Integer;
begin
  mLength := Length(AText);
  mLineStarts := LineStartsOf(AText);
  try
    for mRange in ARanges do
    begin
      if mRange.FileIndex = 0 then
      begin
        BlankRange(AText, OffsetOf(mLineStarts, mRange.Range.StartPos, mLength),
          OffsetOf(mLineStarts, mRange.Range.EndPos, mLength));
      end;
    end;
  finally
    mLineStarts.Free;
  end;
end;

{ TIndexConditions }

class function TIndexConditions.InRange(const APosition: TTextPosition; const ARange: TTextRange): Boolean;
begin
  Result := ((APosition.Line > ARange.StartPos.Line) or
    ((APosition.Line = ARange.StartPos.Line) and (APosition.Character >= ARange.StartPos.Character))) and
    ((APosition.Line < ARange.EndPos.Line) or
    ((APosition.Line = ARange.EndPos.Line) and (APosition.Character < ARange.EndPos.Character)));
end;

class function TIndexConditions.BlankInactive(const AText, AFileName: string; const ADefines: TArray<string>;
  const AResolver: TIncludeResolver; out AIncludes: TArray<string>;
  out AConditionals: TArray<TConditionalRange>): string;
var
  mConditional: TConditionalRange;
  mOptions: TPreprocessorOptions;
  mProcessed: TPreprocessorResult;
  mIndex: Integer;
begin
  Result := AText;
  AIncludes := nil;
  AConditionals := nil;
  if Pos('{$', AText) + Pos('(*$', AText) = 0 then
  begin
    Exit;
  end;
  mOptions := TPreprocessorOptions.Default;
  mOptions.Defines := ADefines;
  mOptions.FileName := AFileName;
  mOptions.ResolveInclude := AResolver;
  mProcessed := TPascalPreprocessor.Process(AText, mOptions);
  for mIndex := 1 to High(mProcessed.Files) do
  begin
    if IndexText(mProcessed.Files[mIndex], AIncludes) < 0 then
    begin
      AIncludes := AIncludes + [mProcessed.Files[mIndex]];
    end;
  end;
  for mConditional in mProcessed.Conditionals do
  begin
    if mConditional.FileIndex = 0 then
    begin
      AConditionals := AConditionals + [mConditional];
    end;
  end;
  if Length(mProcessed.InactiveRanges) > 0 then
  begin
    BlankRanges(Result, mProcessed.InactiveRanges);
  end;
end;

class procedure TIndexConditions.AnnotateConditions(var AUnit: TUnitIndex; const AText: string;
  const AConditionals: TArray<TConditionalRange>);
var
  mLines: TArray<string>;
  mAnnotator: TConditionAnnotator;
  mConditional: TConditionalRange;
begin
  AUnit.Unavailable := nil;
  mLines := AText.Replace(#13#10, #10).Split([#10]);
  MarkActiveConditions(AUnit, mLines, AConditionals);
  // Nur wenn ein Zweig nicht gilt, lohnt die Suche nach Deklarationen darin.
  if not HasInactive(AConditionals) then
  begin
    Exit;
  end;
  mAnnotator := TConditionAnnotator.Create(AUnit.Symbols, mLines);
  try
    for mConditional in AConditionals do
    begin
      if not mConditional.Active then
      begin
        mAnnotator.Scan(mConditional);
      end;
    end;
    AUnit.Unavailable := mAnnotator.Unavailable;
  finally
    mAnnotator.Free;
  end;
end;

{ TConditionAnnotator }

constructor TConditionAnnotator.Create(const ASymbols: TArray<TIndexSymbol>; const ALines: TArray<string>);
var
  mSymbol: TIndexSymbol;
begin
  inherited Create;
  FSymbols := ASymbols;
  FLines := ALines;
  FKnown := TDictionary<string, Boolean>.Create;
  FUnavailable := TList<TIndexSymbol>.Create;
  ReadSections;
  // Was in geltenden Zweigen schon deklariert ist, nicht noch einmal (IFDEF WIN32 ... ELSE ... gleicher Name).
  for mSymbol in FSymbols do
  begin
    FKnown.AddOrSetValue(QualifiedKey(mSymbol.Name, mSymbol.Container), True);
  end;
end;

destructor TConditionAnnotator.Destroy;
begin
  FUnavailable.Free;
  FKnown.Free;
  inherited;
end;

function TConditionAnnotator.Unavailable: TArray<TIndexSymbol>;
begin
  Result := FUnavailable.ToArray;
end;

procedure TConditionAnnotator.ReadSections;
var
  mLine: Integer;
  mSection, mKeyword: string;
begin
  // Ein Durchlauf über die Datei: Abschnitt je Zeile und Beginn des implementation-Teils.
  // Große Units (System.pas) haben tausende Zweige; je Zweig neu zu suchen wäre quadratisch.
  FImplementationLine := -1;
  SetLength(FSections, Length(FLines));
  mSection := '';
  for mLine := 0 to High(FLines) do
  begin
    FSections[mLine] := mSection;
    mKeyword := SectionKeywordOf(FLines[mLine]);
    if (mKeyword = 'implementation') or (mKeyword = 'interface') then
    begin
      mSection := '';
      if (mKeyword = 'implementation') and (FImplementationLine < 0) then
      begin
        FImplementationLine := mLine;
      end;
    end
    else if mKeyword <> '' then
    begin
      mSection := mKeyword;
    end;
  end;
end;

procedure TConditionAnnotator.AddUnavailable(const AName: string; AKind: TIndexSymbolKind; ALine, AColumn: Integer;
  const ACondition, AContainer: string);
var
  mItem: TIndexSymbol;
  mKey: string;
begin
  mKey := QualifiedKey(AName, AContainer);
  if FKnown.ContainsKey(mKey) then
  begin
    Exit;
  end;
  FKnown.Add(mKey, True);
  mItem := Default(TIndexSymbol);
  mItem.Name := AName;
  mItem.Kind := AKind;
  mItem.Container := AContainer;
  mItem.Range := TTextRange.Create(TTextPosition.Create(ALine, 0), TTextPosition.Create(ALine,
    Length(FLines[ALine])));
  mItem.SelectionRange := TTextRange.Create(TTextPosition.Create(ALine, AColumn),
    TTextPosition.Create(ALine, AColumn + Length(AName)));
  mItem.InInterface := (FImplementationLine < 0) or (ALine < FImplementationLine);
  mItem.Visibility := TIndexVisibility.Public;
  mItem.Condition := ACondition;
  mItem.Unavailable := True;
  FUnavailable.Add(mItem);
end;

function TConditionAnnotator.OwnerOf(ALine: Integer): string;
var
  mCandidate: TIndexSymbol;
  mBest: Integer;
begin
  Result := '';
  mBest := -1;
  for mCandidate in FSymbols do
  begin
    if IsBodyAround(mCandidate, ALine) and ((Result = '') or (mCandidate.Range.StartPos.Line >= mBest)) then
    begin
      Result := mCandidate.QualifiedName;
      mBest := mCandidate.Range.StartPos.Line;
    end;
  end;
end;

function TConditionAnnotator.SectionAt(ALine: Integer): string;
begin
  // Abschnitt am Anfang des Zweigs aus dem einen Durchlauf in ReadSections.
  if (ALine >= 0) and (ALine < Length(FSections) - 1) then
  begin
    Result := FSections[ALine + 1];
  end
  else
  begin
    Result := '';
  end;
end;

function TConditionAnnotator.LastLine(const AConditional: TConditionalRange): Integer;
begin
  Result := Min(AConditional.Range.EndPos.Line, High(FLines));
end;

function TConditionAnnotator.AddRoutine(const ACode: string; ALine: Integer; const ACondition: string): Boolean;
var
  mMatch: TMatch;
begin
  mMatch := TRegEx.Match(ACode, RoutinePattern, [roIgnoreCase]);
  Result := mMatch.Success;
  if Result then
  begin
    AddUnavailable(mMatch.Groups[2].Value, TIndexSymbolKind.Routine, ALine, mMatch.Groups[2].Index - 1,
      ACondition, '');
  end;
end;

function TConditionAnnotator.AddMethodMember(const ACode: string; ALine: Integer;
  const AOwner, ACondition: string): Boolean;
var
  mMatch: TMatch;
  mKind: TIndexSymbolKind;
begin
  mMatch := TRegEx.Match(ACode,
    '^\s*(class\s+)?(procedure|function|constructor|destructor|operator)\s+([A-Za-z_]\w*)', [roIgnoreCase]);
  Result := mMatch.Success;
  if not Result then
  begin
    Exit;
  end;
  if SameText(mMatch.Groups[2].Value, 'constructor') then
  begin
    mKind := TIndexSymbolKind.Constructor_;
  end
  else
  begin
    mKind := TIndexSymbolKind.Method;
  end;
  AddUnavailable(mMatch.Groups[3].Value, mKind, ALine, mMatch.Groups[3].Index - 1, ACondition, AOwner);
end;

function TConditionAnnotator.AddPropertyMember(const ACode: string; ALine: Integer;
  const AOwner, ACondition: string): Boolean;
var
  mMatch: TMatch;
begin
  mMatch := TRegEx.Match(ACode, '^\s*(class\s+)?property\s+([A-Za-z_]\w*)', [roIgnoreCase]);
  Result := mMatch.Success;
  if Result then
  begin
    AddUnavailable(mMatch.Groups[2].Value, TIndexSymbolKind.Property_, ALine, mMatch.Groups[2].Index - 1,
      ACondition, AOwner);
  end;
end;

procedure TConditionAnnotator.AddFieldMembers(const ACode: string; ALine: Integer; const AOwner, ACondition: string);
var
  mMatch: TMatch;
  mName, mWord: string;
  mColumn: Integer;
begin
  // Felder "A, B: Integer;" (auch nach "class var" / "var"); Schlüsselwörter sind keine Felder.
  mMatch := TRegEx.Match(ACode, '^\s*((class\s+)?var\s+)?([A-Za-z_]\w*(\s*,\s*[A-Za-z_]\w*)*)\s*:[^=]',
    [roIgnoreCase]);
  if not mMatch.Success then
  begin
    Exit;
  end;
  mColumn := mMatch.Groups[3].Index - 1;
  for mName in mMatch.Groups[3].Value.Split([',']) do
  begin
    mWord := Trim(mName);
    if not MatchText(mWord, ['private', 'protected', 'public', 'published', 'strict', 'case', 'end']) then
    begin
      AddUnavailable(mWord, TIndexSymbolKind.Field, ALine, mColumn + Pos(mWord, mMatch.Groups[3].Value) - 1,
        ACondition, AOwner);
    end;
  end;
end;

procedure TConditionAnnotator.AddNamed(const ACode, APattern: string; AKind: TIndexSymbolKind; ALine: Integer;
  const ACondition: string);
var
  mMatch: TMatch;
begin
  mMatch := TRegEx.Match(ACode, APattern, [roIgnoreCase]);
  if mMatch.Success then
  begin
    AddUnavailable(mMatch.Groups[1].Value, AKind, ALine, mMatch.Groups[1].Index - 1, ACondition, '');
  end;
end;

procedure TConditionAnnotator.AddTypeDeclaration(const ACode: string; ALine: Integer; const ACondition: string);
var
  mMatch: TMatch;
begin
  // Vorwärtsdeklaration "TFoo = class;" zählt nicht.
  if TRegEx.IsMatch(ACode, '=\s*(packed\s+)?(class|interface)\s*;', [roIgnoreCase]) then
  begin
    Exit;
  end;
  mMatch := TRegEx.Match(ACode, '^\s*([A-Za-z_]\w*)\s*(<[^>]*>)?\s*=\s*(packed\s+)?(\w+|\()', [roIgnoreCase]);
  if mMatch.Success then
  begin
    AddUnavailable(mMatch.Groups[1].Value, TypeKindOf(LowerCase(mMatch.Groups[4].Value)), ALine,
      mMatch.Groups[1].Index - 1, ACondition, '');
  end;
end;

procedure TConditionAnnotator.AddDeclaration(const ACode, ASection: string; ALine: Integer;
  const ACondition: string);
begin
  if ASection = 'type' then
  begin
    AddTypeDeclaration(ACode, ALine, ACondition);
  end
  else if (ASection = 'const') or (ASection = 'resourcestring') then
  begin
    AddNamed(ACode, '^\s*([A-Za-z_]\w*)\s*(:[^=]+)?=', TIndexSymbolKind.Constant, ALine, ACondition);
  end
  else if (ASection = 'var') or (ASection = 'threadvar') then
  begin
    AddNamed(ACode, '^\s*([A-Za-z_]\w*)\s*:', TIndexSymbolKind.Variable, ALine, ACondition);
  end;
end;

procedure TConditionAnnotator.ScanRoutines(const AConditional: TConditionalRange);
var
  mLine: Integer;
begin
  // Im implementation-Teil nur Routinen der Unit (eigene Unit, z. B. "procedure ApplyAppIcon;" unter
  // {$IFDEF FPC}): ein billiger Vergleich am Zeilenanfang je Zeile, denn lange Zweige mit ganzen
  // Implementierungen (System.pas) sollen nichts kosten. Methodenrümpfe "TFoo.Bar" zählen nicht.
  for mLine := AConditional.Range.StartPos.Line + 1 to LastLine(AConditional) do
  begin
    if StartsText('procedure ', FLines[mLine]) or StartsText('function ', FLines[mLine]) then
    begin
      AddRoutine(FLines[mLine], mLine, AConditional.Condition);
    end;
  end;
end;

procedure TConditionAnnotator.ScanMembers(const AConditional: TConditionalRange; const AOwner: string);
var
  mLine: Integer;
  mCode: string;
begin
  // Mitglied in einem nicht geltenden Zweig innerhalb eines Typrumpfs (#476): Methoden, Properties, Felder.
  for mLine := AConditional.Range.StartPos.Line + 1 to LastLine(AConditional) do
  begin
    mCode := WithoutComment(FLines[mLine]);
    if not AddMethodMember(mCode, mLine, AOwner, AConditional.Condition) and
      not AddPropertyMember(mCode, mLine, AOwner, AConditional.Condition) then
    begin
      AddFieldMembers(mCode, mLine, AOwner, AConditional.Condition);
    end;
  end;
end;

procedure TConditionAnnotator.ScanDeclarationLine(ALine: Integer; const ACondition: string; var ASection: string);
var
  mCode: string;
  mMatch: TMatch;
begin
  mCode := WithoutComment(FLines[ALine]);
  mMatch := TRegEx.Match(mCode, '^\s*(type|const|var|threadvar|resourcestring)\b', [roIgnoreCase]);
  if mMatch.Success then
  begin
    ASection := LowerCase(mMatch.Groups[1].Value);
    mCode := Copy(mCode, mMatch.Length + 1, MaxInt);
    if Trim(mCode) = '' then
    begin
      Exit;
    end;
  end;
  // Routinen auf Unit-Ebene stehen am Zeilenanfang.
  if AddRoutine(mCode, ALine, ACondition) then
  begin
    ASection := '';
  end
  else if TTextLines.IndentLength(FLines[ALine]) <= 2 then
  begin
    AddDeclaration(mCode, ASection, ALine, ACondition);
  end;
end;

procedure TConditionAnnotator.ScanDeclarations(const AConditional: TConditionalRange);
var
  mSection: string;
  mLine: Integer;
begin
  mSection := SectionAt(AConditional.Range.StartPos.Line);
  for mLine := AConditional.Range.StartPos.Line + 1 to LastLine(AConditional) do
  begin
    ScanDeclarationLine(mLine, AConditional.Condition, mSection);
  end;
end;

procedure TConditionAnnotator.Scan(const AConditional: TConditionalRange);
var
  mOwner: string;
begin
  if (FImplementationLine >= 0) and (AConditional.Range.StartPos.Line > FImplementationLine) then
  begin
    ScanRoutines(AConditional);
    Exit;
  end;
  // Zweig im Rumpf einer Klasse, eines Records oder Interfaces: Mitglieder dieses Typs.
  mOwner := OwnerOf(AConditional.Range.StartPos.Line);
  if mOwner <> '' then
  begin
    ScanMembers(AConditional, mOwner);
  end
  else
  begin
    ScanDeclarations(AConditional);
  end;
end;

end.
