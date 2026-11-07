unit Atlas.Common.Editing.TypeCommands;

// Schnellbefehle, die Typen erzeugen oder umbauen (#298), im Rahmen aus #293:
//   /enum TFarbe rot, gruen [names]  Aufzählung mit Präfix (/enum! ohne), mit names auch Namenstabelle
//   /helper TTyp                     record helper bzw. class helper für TTyp; bei Aufzählungen mit
//                                    Namenstabelle cNames, ToString und FromString (#875,
//                                    slashCommands.enumHelper); bei Mengen Contains, ToText, Toggle
//                                    und All (slashCommands.setHelper)
//   /singleton                       class var FInstance, Instance und class destructor
//   /encapsulate FName               Feld wird private, dazu Property Name mit Setter
//   /assign                          Assign(Source: TPersistent) für alle Felder
//   /json                            ToJson und FromJson mit System.JSON für einfache Felder
//   /thread TWorker                  TThread-Nachfahre mit Execute-Schleife (#299)
//   /exception EName [: EBasis]      Ausnahmeklasse (#304)

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Editing.Contract,
  Atlas.Common.Editing.CommandSource;

/// <summary>Trägt die Typbefehle über ARegister ein.</summary>
procedure RegisterTypeCommands(const ARegister: TSlashRegister);

/// <summary>Präfix aus den Großbuchstaben des Typnamens ohne führendes T, klein: TKundenStatus wird ks.</summary>
function EnumPrefix(const ATypeName: string): string;
/// <summary>Ist ATypeName eine Klasse (in der Datei, im Index oder bekannt aus RTL/VCL)?</summary>
function IsClassType(ASource: TCommandSource; const AIndex: ISymbolIndex; const ATypeName: string): Boolean;

// Bausteine für weitere Typbefehle (#323).

/// <summary>Steht die Befehlszeile auf Unit-Ebene? AInTypeSection, wenn sie in einem type-Abschnitt steht.</summary>
function TypePlace(ASource: TCommandSource; const AName: string; out AInTypeSection: Boolean;
  out AReason: string): Boolean;
/// <summary>Ersetzt die Befehlszeile durch ALines; ohne type-Abschnitt kommt "type" davor.</summary>
function TypeDeclaration(ASource: TCommandSource; AInTypeSection: Boolean; const ALines: array of string): TTextEdit;
/// <summary>Deklarationen vor "end" der Klasse, Rümpfe hinter ihre letzte Methode.</summary>
function AddToClass(ASource: TCommandSource; const AClass: TIndexSymbol; const ADeclarations: array of string;
  const ABodies: string): TArray<TTextEdit>;
/// <summary>ALines mit dem Zeilenende der Datei verbunden.</summary>
function Join(ASource: TCommandSource; const ALines: array of string): string;
/// <summary>Felder von AClass in der Datei.</summary>
function FieldsOf(ASource: TCommandSource; const AClass: TIndexSymbol): TArray<TIndexSymbol>;
/// <summary>Ist das Feld ein Objekt (Klassentyp, kein einfacher Typ)?</summary>
function IsObjectField(ASource: TCommandSource; const AIndex: ISymbolIndex; const AField: TIndexSymbol): Boolean;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Editing.UsesClause,
  Atlas.Common.Editing.ClassMembers,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TTypeCommandsText = (OnlyAppliesInAUnit, ExpectedIsEnumTTypeValue1, OnlyOneHelperPerType,
    RaiseEArgumentExceptionCreateFmtUnknownValue, ExpectedIsHelperTType, OnlyAppliesInAClass,
    SingletonConstructorStaysUnchangedAnd, SingletonOnlyAppliesInA, NoFieldIn, IsAlreadyPrivate,
    ExpectedIsEncapsulateFName, EncapsulateOnlyAppliesInA, AssignOnlyAppliesInA, ExpectedIsExceptionENameEBase,
    ExpectedIsThreadTName, IfNobodyWaitsForThe, CreateAnEnumerationTypeWith, CreateAnEnumerationTypeWithout,
    MakeTheClassASingleton, ConvertAFieldIntoA, CreateAssignForAllFields, CreateToJsonAndFromJson,
    CreateATThreadDescendantWith, OnlyAppliesAtUnitLevel, AlreadyExistsIn, MustBeDeclaredAloneOn,
    ShowResultsInTheMain, CreateARecordOrClass, CreateAnExceptionClass, EnumTColorRedGreenBlue, EnumTColorRedGreen,
    HelperTColor, ExceptionEImportError);

const
  cTexts: array[TTypeCommandsText] of TAtlasText = (
    (De: '/%s gilt nur in einer Unit'; En: '/%s only applies in a unit'),
    (De: 'Erwartet wird /enum TTyp wert1, wert2 [names]'; En: 'Expected is /enum TType value1, value2 [names]'),
    (De: '// Nur ein Helper je Typ ist wirksam: der zuletzt sichtbare.';
     En: '// Only one helper per type takes effect: the last visible one.'),
    (De: '  raise EArgumentException.CreateFmt(''Unbekannter Wert "%%s" für %s'', [AValue]);';
     En: '  raise EArgumentException.CreateFmt(''Unknown value "%%s" for %s'', [AValue]);'),
    (De: 'Erwartet wird /helper TTyp'; En: 'Expected is /helper TType'),
    (De: '/%s gilt nur in einer Klasse oder einer ihrer Methoden';
     En: '/%s only applies in a class or one of its methods'),
    (De: '/singleton: Konstruktor %s bleibt unverändert und öffentlich; Instance ruft Create ohne Parameter';
     En: '/singleton: constructor %s stays unchanged and public; Instance calls Create without parameters'),
    (De: '/singleton gilt nur in einer Klasse oder einer ihrer Methoden';
     En: '/singleton only applies in a class or one of its methods'),
    (De: 'Kein Feld %s in '; En: 'No field %s in '),
    (De: ' ist schon private'; En: ' is already private'),
    (De: 'Erwartet wird /encapsulate FName'; En: 'Expected is /encapsulate FName'),
    (De: '/encapsulate gilt nur in einer Klasse oder einer ihrer Methoden';
     En: '/encapsulate only applies in a class or one of its methods'),
    (De: '/assign gilt nur in einer Klasse oder einer ihrer Methoden';
     En: '/assign only applies in a class or one of its methods'),
    (De: 'Erwartet wird /exception EName [: EBasis]'; En: 'Expected is /exception EName [: EBase]'),
    (De: 'Erwartet wird /thread TName'; En: 'Expected is /thread TName'),
    (De: '  // Wartet niemand auf den Thread, im Konstruktor FreeOnTerminate := True setzen.';
     En: '  // If nobody waits for the thread, set FreeOnTerminate := True in the constructor.'),
    (De: 'Aufzählungstyp mit Präfix anlegen'; En: 'Create an enumeration type with prefix'),
    (De: 'Aufzählungstyp ohne Präfix anlegen'; En: 'Create an enumeration type without prefix'),
    (De: 'Klasse zum Singleton machen'; En: 'Make the class a singleton'),
    (De: 'Feld in Property mit Setter umwandeln'; En: 'Convert a field into a property with setter'),
    (De: 'Assign für alle Felder anlegen'; En: 'Create Assign for all fields'),
    (De: 'ToJson und FromJson anlegen'; En: 'Create ToJson and FromJson'),
    (De: 'TThread-Nachfahre mit Execute anlegen'; En: 'Create a TThread descendant with Execute'),
    (De: '/%s gilt nur auf Unit-Ebene'; En: '/%s only applies at unit level'),
    (De: '%s gibt es schon in %s'; En: '%s already exists in %s'),
    (De: ' muss allein in seiner Zeile deklariert sein'; En: ' must be declared alone on its line'),
    (De: '    // Ergebnisse im Hauptthread zeigen: TThread.Queue(nil, procedure begin … end);';
     En: '    // Show results in the main thread: TThread.Queue(nil, procedure begin … end);'),
    (De: 'Record- bzw. Class-Helper anlegen'; En: 'Create a record or class helper'),
    (De: 'Ausnahmeklasse anlegen'; En: 'Create an exception class'),
    (De: '/enum TFarbe rot, gruen, blau names'; En: '/enum TColor red, green, blue names'),
    (De: '/enum! TFarbe rot, gruen'; En: '/enum! TColor red, green'),
    (De: '/helper TFarbe'; En: '/helper TColor'),
    (De: '/exception EImportFehler'; En: '/exception EImportError'));

{$SCOPEDENUMS OFF}

const
  // Typen, die per Zuweisung kopiert und als JSON-Wert geschrieben werden.
  cStringTypes: array[0..5] of string = ('string', 'UnicodeString', 'AnsiString', 'WideString', 'Char', 'TCaption');
  cIntegerTypes: array[0..10] of string = ('Integer', 'Cardinal', 'Int64', 'UInt64', 'Byte', 'Word', 'SmallInt',
    'ShortInt', 'LongInt', 'NativeInt', 'TColor');
  cFloatTypes: array[0..5] of string = ('Double', 'Single', 'Extended', 'Currency', 'Real', 'TDateTime');
  // Bekannte Klassen aus RTL und VCL, die Assign können.
  cPersistentTypes: array[0..10] of string = ('TStrings', 'TStringList', 'TPersistent', 'TCollection', 'TFont',
    'TBitmap', 'TPicture', 'TPen', 'TBrush', 'TIcon', 'TGraphic');

function EnumPrefix(const ATypeName: string): string;
var
  mIndex: Integer;
begin
  Result := '';
  for mIndex := 2 to Length(ATypeName) do
  begin
    if CharInSet(ATypeName[mIndex], ['A'..'Z']) then
    begin
      Result := Result + LowerCase(ATypeName[mIndex]);
    end;
  end;
  if Result = '' then
  begin
    Result := LowerCase(Copy(ATypeName, 1, 1));
  end;
end;

function Capitalize(const AText: string): string;
begin
  Result := UpperCase(Copy(AText, 1, 1)) + Copy(AText, 2, MaxInt);
end;

/// <summary>Liegt Zeile ALine in einem type-Abschnitt des interface- oder implementation-Teils?</summary>
function InTypeSectionAt(ATree: TSyntaxTree; ALine: Integer): Boolean;
var
  mSection: TSyntaxNode;
  mIndex, mChild: Integer;
begin
  Result := False;
  for mIndex := 0 to ATree.Root.ChildCount - 1 do
  begin
    mSection := ATree.Root[mIndex];
    if not (mSection.Kind in [TSyntaxKind.InterfaceSection, TSyntaxKind.ImplementationSection]) then
    begin
      Continue;
    end;
    for mChild := 0 to mSection.ChildCount - 1 do
    begin
      if (mSection[mChild].Kind = TSyntaxKind.TypeSection) and (mSection[mChild].StartPos.Line <= ALine) and
        (mSection[mChild].EndPos.Line >= ALine) then
      begin
        Result := True;
      end;
    end;
  end;
end;

/// <summary>Letzte Zeile mit Text vor der Befehlszeile; -1 ohne.</summary>
function PreviousCodeLine(ASource: TCommandSource): Integer;
begin
  Result := ASource.Line - 1;
  while (Result >= 0) and (Trim(ASource.Lines[Result]) = '') do
  begin
    Dec(Result);
  end;
end;

/// <summary>Steht die Befehlszeile in einem type-Abschnitt (nicht in Klasse oder Routine)?
/// False mit Grund, wenn dort kein Typ stehen darf.</summary>
function TypePlace(ASource: TCommandSource; const AName: string; out AInTypeSection: Boolean;
  out AReason: string): Boolean;
var
  mClassSymbol: TIndexSymbol;
begin
  AInTypeSection := False;
  if (ASource.RoutineAt <> nil) or ASource.ClassAt(mClassSymbol) then
  begin
    Exit(Fail(cTexts[TTypeCommandsText.OnlyAppliesAtUnitLevel].Fmt([AName]), AReason));
  end;
  // type-Abschnitt, der die vorige Zeile mit Code enthält.
  AInTypeSection := InTypeSectionAt(ASource.Tree, PreviousCodeLine(ASource));
  if ASource.Tree.Root.FindChild(TSyntaxKind.InterfaceSection) = nil then
  begin
    Exit(Fail(cTexts[TTypeCommandsText.OnlyAppliesInAUnit].Fmt([AName]), AReason));
  end;
  Result := True;
end;

/// <summary>Beginnt die nächste Zeile mit einer weiteren Typdeklaration (Name = …)?</summary>
function TypeFollows(ASource: TCommandSource): Boolean;
var
  mNext: Integer;
  mLine: string;
begin
  mNext := ASource.Line + 1;
  while (mNext <= High(ASource.Lines)) and (Trim(ASource.Lines[mNext]) = '') do
  begin
    Inc(mNext);
  end;
  if mNext > High(ASource.Lines) then
  begin
    Exit(False);
  end;
  mLine := Trim(ASource.Lines[mNext]);
  Result := (Pos('=', mLine) > 1) and IsValidIdent(Trim(Copy(mLine, 1, Pos('=', mLine) - 1)));
end;

/// <summary>Ersetzt die Befehlszeile durch ALines; ohne type-Abschnitt kommt "type" davor.</summary>
function TypeDeclaration(ASource: TCommandSource; AInTypeSection: Boolean; const ALines: array of string): TTextEdit;
var
  mIndent, mText: string;
  mIndex: Integer;
begin
  mText := '';
  mIndent := '  ';
  if AInTypeSection then
  begin
    mIndent := ASource.Indent(ASource.Line);
  end
  else
  begin
    mText := 'type' + ASource.LineBreak;
  end;
  for mIndex := 0 to High(ALines) do
  begin
    if StartsStr('#', ALines[mIndex]) then
    begin
      mText := mText + Copy(ALines[mIndex], 2, MaxInt) + ASource.LineBreak;
    end
    else
    begin
      mText := mText + mIndent + ALines[mIndex] + ASource.LineBreak;
    end;
  end;
  Result := TTextEdit.Create(TTextRange.Create(ASource.Line, 0, ASource.Line + 1, 0), mText);
end;

{ /enum }

/// <summary>Liest "TTyp wert1, wert2 [names]"; False, wenn Typname oder ein Wert kein Bezeichner ist.</summary>
function EnumArguments(const AArguments: string; out ATypeName: string; out AValues: TArray<string>;
  out AWithNames: Boolean): Boolean;
var
  mArguments: string;
  mSpace, mIndex: Integer;
begin
  mArguments := Trim(AArguments);
  AWithNames := EndsText(' names', mArguments);
  if AWithNames then
  begin
    mArguments := Trim(Copy(mArguments, 1, Length(mArguments) - 6));
  end;
  mSpace := Pos(' ', mArguments);
  ATypeName := Copy(mArguments, 1, mSpace - 1);
  AValues := Copy(mArguments, mSpace + 1, MaxInt).Split([',']);
  Result := (mSpace > 0) and IsValidIdent(ATypeName) and (Length(AValues) > 0);
  for mIndex := 0 to High(AValues) do
  begin
    AValues[mIndex] := Trim(AValues[mIndex]);
    Result := Result and IsValidIdent(AValues[mIndex]);
  end;
end;

/// <summary>Werte der Aufzählung, mit APrefixed als Präfix von ATypeName plus Wert mit großem Anfang.</summary>
function EnumMemberList(const ATypeName: string; const AValues: TArray<string>; APrefixed: Boolean): string;
var
  mPrefix, mValue: string;
begin
  mPrefix := EnumPrefix(ATypeName);
  Result := '';
  for mValue in AValues do
  begin
    if Result <> '' then
    begin
      Result := Result + ', ';
    end;
    if APrefixed then
    begin
      Result := Result + mPrefix + Capitalize(mValue);
    end
    else
    begin
      Result := Result + mValue;
    end;
  end;
end;

/// <summary>Werte als Strings für die Namenstabelle.</summary>
function QuotedList(const AValues: TArray<string>): string;
var
  mValue: string;
begin
  Result := '';
  for mValue in AValues do
  begin
    if Result <> '' then
    begin
      Result := Result + ', ';
    end;
    Result := Result + QuotedStr(mValue);
  end;
end;

function ExecuteEnum(const AContext: TSlashContext; APrefixed: Boolean; out AEdits: TArray<TTextEdit>;
  out AReason: string): Boolean;
var
  mSource: TCommandSource;
  mTypeName: string;
  mValues, mLines: TArray<string>;
  mWithNames, mInTypeSection: Boolean;
begin
  AEdits := nil;
  if not EnumArguments(AContext.Arguments, mTypeName, mValues, mWithNames) then
  begin
    Exit(Fail(cTexts[TTypeCommandsText.ExpectedIsEnumTTypeValue1].Text, AReason));
  end;
  mSource := TCommandSource.Create(AContext);
  try
    Result := TypePlace(mSource, AContext.Name, mInTypeSection, AReason);
    if not Result then
    begin
      Exit;
    end;
    mLines := [Format('%s = (%s);', [mTypeName, EnumMemberList(mTypeName, mValues, APrefixed)])];
    if mWithNames then
    begin
      mLines := mLines + ['#const', Format('#  %sNamen: array[%s] of string = (%s);',
        [Copy(mTypeName, 2, MaxInt), mTypeName, QuotedList(mValues)])];
      // Folgen weitere Typen, braucht es wieder "type".
      if TypeFollows(mSource) then
      begin
        mLines := mLines + ['#type'];
      end;
    end;
    AEdits := [TypeDeclaration(mSource, mInTypeSection, mLines)];
  finally
    mSource.Free;
  end;
end;

{ /helper }

/// <summary>Ist ATypeName eine Klasse (in der Datei oder im Index)?</summary>
function IsClassType(ASource: TCommandSource; const AIndex: ISymbolIndex; const ATypeName: string): Boolean;
var
  mSymbol: TIndexSymbol;
  mLocation: TSymbolLocation;
begin
  for mSymbol in ASource.UnitIndex.Symbols do
  begin
    if SameText(mSymbol.Name, ATypeName) and (mSymbol.Container = '') then
    begin
      Exit(mSymbol.Kind = TIndexSymbolKind.ClassType);
    end;
  end;
  if AIndex <> nil then
  begin
    for mLocation in AIndex.FindSymbols(ATypeName) do
    begin
      if mLocation.Symbol.Kind = TIndexSymbolKind.ClassType then
      begin
        Exit(True);
      end;
    end;
  end;
  Result := MatchText(ATypeName, cPersistentTypes) or MatchText(ATypeName, ['TObject', 'TComponent', 'TControl',
    'TForm', 'TFrame', 'TList', 'TStream']);
end;

/// <summary>Werte der Aufzählung ATypeName in Deklarationsreihenfolge, aus der Datei oder dem Index; False, wenn
/// ATypeName keine bekannte Aufzählung ist.</summary>
function EnumMembers(ASource: TCommandSource; const AIndex: ISymbolIndex; const ATypeName: string;
  out AValues: TArray<string>): Boolean;

  function Collect(const AUnit: TUnitIndex; const AName: string): Boolean;
  var
    mSymbol: TIndexSymbol;
  begin
    for mSymbol in AUnit.Symbols do
    begin
      if (mSymbol.Kind = TIndexSymbolKind.EnumMember) and SameText(mSymbol.Container, AName) then
      begin
        AValues := AValues + [mSymbol.Name];
      end;
    end;
    Result := AValues <> nil;
  end;

var
  mSymbol: TIndexSymbol;
  mLocation: TSymbolLocation;
  mOwner: TUnitIndex;
  mName: string;
begin
  AValues := nil;
  // Unit.TTyp: gesucht wird der einfache Name.
  mName := ATypeName;
  if Pos('.', mName) > 0 then
  begin
    mName := Copy(mName, LastDelimiter('.', mName) + 1, MaxInt);
  end;
  for mSymbol in ASource.UnitIndex.Symbols do
  begin
    if SameText(mSymbol.Name, mName) and (mSymbol.Container = '') then
    begin
      Exit((mSymbol.Kind = TIndexSymbolKind.EnumType) and Collect(ASource.UnitIndex, mSymbol.Name));
    end;
  end;
  if AIndex <> nil then
  begin
    for mLocation in AIndex.FindSymbols(mName) do
    begin
      if (mLocation.Symbol.Kind = TIndexSymbolKind.EnumType) and (mLocation.Symbol.Container = '') and
        AIndex.FindFile(mLocation.FileName, mOwner) and Collect(mOwner, mLocation.Symbol.Name) then
      begin
        Exit(True);
      end;
    end;
  end;
  Result := False;
end;

/// <summary>Namenstabelle cNames; lange Listen umbrechen nach Kommas.</summary>
function NamesConstant(const ATypeName: string; const AValues: TArray<string>): TArray<string>;
const
  cMaxWidth = 100;
var
  mLine: string;
  mIndex: Integer;
begin
  Result := nil;
  mLine := Format('  cNames: array[%s] of string = (', [ATypeName]);
  for mIndex := 0 to High(AValues) do
  begin
    if (mIndex > 0) and (Length(mLine) + Length(AValues[mIndex]) + 4 > cMaxWidth) then
    begin
      Result := Result + [mLine];
      mLine := '   ';
    end;
    mLine := mLine + QuotedStr(AValues[mIndex]);
    if mIndex < High(AValues) then
    begin
      mLine := mLine + ', ';
    end
    else
    begin
      mLine := mLine + ');';
    end;
  end;
  Result := Result + [TrimRight(mLine)];
end;

/// <summary>Elementtyp des Mengentyps ADecl ("set of TElement"); '' bei namenloser Aufzählung.</summary>
function SetElementOf(ADecl: TSyntaxNode): string;
var
  mBody: TSyntaxNode;
begin
  Result := '';
  mBody := ADecl.FindChild(TSyntaxKind.SetType);
  if (mBody <> nil) and (mBody.ChildCount > 0) and (mBody[0].Kind = TSyntaxKind.TypeReference) then
  begin
    Result := mBody[0].Name;
  end;
end;

function SetElementIn(ATree: TSyntaxTree; const ATypeName: string; out AElement: string): Boolean;
var
  mTypeName: string;
  mFound: TSyntaxNode;
begin
  AElement := '';
  if (ATree = nil) or (ATree.Root = nil) then
  begin
    Exit(False);
  end;
  mTypeName := ATypeName;
  // Search statt Rekursion (Bericht M1); in einen gleichnamigen Typ ohne Element geht die Suche nicht hinein.
  mFound := ATree.Root.Search(
    function(ANode: TSyntaxNode): TSyntaxSearchStep
    begin
      Result := TSyntaxSearchStep.Descend;
      if (ANode.Kind <> TSyntaxKind.TypeDecl) or not SameText(ANode.Name, mTypeName) then
      begin
        Exit;
      end;
      Result := TSyntaxSearchStep.Skip;
      if SetElementOf(ANode) <> '' then
      begin
        Result := TSyntaxSearchStep.Found;
      end;
    end);
  Result := mFound <> nil;
  if Result then
  begin
    AElement := SetElementOf(mFound);
  end;
end;

/// <summary>Elementtyp der Menge AName aus der Datei AFileName, gelesen über den Host.</summary>
function FileSetElement(const AContext: TSlashContext; const AFileName, AName: string; out AElement: string): Boolean;
var
  mText: string;
  mTree: TSyntaxTree;
begin
  AElement := '';
  if not AContext.Host.ReadFile(AFileName, mText) then
  begin
    Exit(False);
  end;
  mTree := TSyntaxTreeCache.Parse(mText);
  try
    Result := SetElementIn(mTree, AName, AElement);
  finally
    mTree.Free;
  end;
end;

/// <summary>Elementtyp der Menge AName aus der Unit, die der Index nennt; False ohne Index oder Host.</summary>
function IndexedSetElement(const AContext: TSlashContext; const AName: string; out AElement: string): Boolean;
var
  mLocation: TSymbolLocation;
begin
  AElement := '';
  if (AContext.Index = nil) or (AContext.Host = nil) then
  begin
    Exit(False);
  end;
  for mLocation in AContext.Index.FindSymbols(AName) do
  begin
    if (mLocation.Symbol.Kind = TIndexSymbolKind.TypeAlias) and (mLocation.Symbol.Container = '') and
      FileSetElement(AContext, mLocation.FileName, AName, AElement) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Elementtyp der Menge ATypeName: aus der Datei, sonst aus der Unit, die der Index nennt (#875).</summary>
function SetElement(ASource: TCommandSource; const AContext: TSlashContext; const ATypeName: string;
  out AElement: string): Boolean;
var
  mName: string;
begin
  mName := ATypeName;
  if Pos('.', mName) > 0 then
  begin
    mName := Copy(mName, LastDelimiter('.', mName) + 1, MaxInt);
  end;
  Result := SetElementIn(ASource.Tree, mName, AElement) or IndexedSetElement(AContext, mName, AElement);
end;

/// <summary>Helper für eine Menge (#875): Contains, ToText, Toggle und All.</summary>
function SetHelper(ASource: TCommandSource; const AContext: TSlashContext; AInTypeSection: Boolean;
  const ATypeName, AHelperName, AElement: string): TArray<TTextEdit>;
var
  mValues, mLines, mToText, mBody: TArray<string>;
begin
  mLines := [cTexts[TTypeCommandsText.OnlyOneHelperPerType].Text,
    Format('%s = record helper for %s', [AHelperName, ATypeName])];
  // Mit bekannten Werten eine Namenstabelle, sonst die Namen aus der RTTI.
  if EnumMembers(ASource, AContext.Index, AElement, mValues) then
  begin
    mLines := mLines + ['private const'] + NamesConstant(AElement, mValues);
    mToText := ['    Result := Result + cNames[Value];'];
  end
  else
  begin
    mToText := ['    Result := Result + GetEnumName(TypeInfo(' + AElement + '), Ord(Value));'];
  end;
  mLines := mLines + ['public', Format('  function Contains(AValue: %s): Boolean;', [AElement]),
    '  function ToText: string;', Format('  procedure Toggle(AValue: %s);', [AElement]),
    Format('  class function All: %s; static;', [ATypeName]), 'end;'];
  mBody := [Format('function %s.Contains(AValue: %s): Boolean;', [AHelperName, AElement]), 'begin',
    '  Result := AValue in Self;', 'end;', '',
    Format('function %s.ToText: string;', [AHelperName]), 'var', Format('  Value: %s;', [AElement]), 'begin',
    '  Result := '''';', '  for Value in Self do', '  begin', '    if Result <> '''' then',
    '      Result := Result + '', '';'];
  mBody := mBody + mToText;
  mBody := mBody + ['  end;', '  Result := ''['' + Result + '']'';', 'end;', '',
    Format('procedure %s.Toggle(AValue: %s);', [AHelperName, AElement]), 'begin', '  if AValue in Self then',
    '    Exclude(Self, AValue)', '  else', '    Include(Self, AValue);', 'end;', '',
    Format('class function %s.All: %s;', [AHelperName, ATypeName]), 'begin',
    Format('  Result := [Low(%s)..High(%s)];', [AElement, AElement]), 'end;'];
  Result := [TypeDeclaration(ASource, AInTypeSection, mLines), ASource.AddBody(AHelperName, Join(ASource, mBody))];
end;

/// <summary>Trägt AUnitName ins uses ein, wenn sie dort fehlt; der Eintrag gilt für die Stelle in Zeile
/// ALine.</summary>
procedure AddMissingUses(ASource: TCommandSource; const AContext: TSlashContext; const AUnitName: string;
  ALine: Integer; var AEdits: TArray<TTextEdit>);
var
  mUsesEdit: TTextEdit;
begin
  if not TUsesClauses.IsUsed(TUsesClauses.UsedUnits(ASource.Tree.Tokens), AUnitName, AContext.Namespaces) and
    TUsesClauses.AddUnit(ASource.Tree.Tokens, ASource.Offset(ALine), AUnitName, ASource.LineBreak, mUsesEdit) then
  begin
    AEdits := AEdits + [mUsesEdit];
  end;
end;

/// <summary>Ist die Einstellung AKey eingeschaltet? Ohne Host gilt sie als an.</summary>
function SettingOn(const AContext: TSlashContext; const AKey: string): Boolean;
begin
  Result := (AContext.Host = nil) or not SameText(AContext.Host.Setting(AContext.Uri, AKey), 'false');
end;

/// <summary>Helper für eine Aufzählung (#875): Namenstabelle, ToString und FromString.</summary>
function EnumHelper(ASource: TCommandSource; AInTypeSection: Boolean; const ATypeName, AHelperName: string;
  const AValues: TArray<string>): TArray<TTextEdit>;
var
  mLines: TArray<string>;
begin
  mLines := [cTexts[TTypeCommandsText.OnlyOneHelperPerType].Text,
    Format('%s = record helper for %s', [AHelperName, ATypeName]), 'private const'];
  mLines := mLines + NamesConstant(ATypeName, AValues);
  mLines := mLines + ['public', '  function ToString: string;',
    Format('  class function FromString(const AValue: string): %s; static;', [ATypeName]), 'end;'];
  Result := [TypeDeclaration(ASource, AInTypeSection, mLines),
    ASource.AddBody(AHelperName, Join(ASource, [
    Format('function %s.ToString: string;', [AHelperName]), 'begin', '  Result := cNames[Self];', 'end;', '',
    Format('class function %s.FromString(const AValue: string): %s;', [AHelperName, ATypeName]), 'var',
    Format('  Value: %s;', [ATypeName]), 'begin', Format('  for Value := Low(%s) to High(%s) do', [ATypeName,
    ATypeName]), '    if SameText(cNames[Value], AValue) then', '      Exit(Value);',
    cTexts[TTypeCommandsText.RaiseEArgumentExceptionCreateFmtUnknownValue].Fmt([ATypeName]),
    'end;']))];
end;

/// <summary>Leerer Helper AHelperName der Art AKind (record bzw. class) für ATypeName.</summary>
function PlainHelper(ASource: TCommandSource; AInTypeSection: Boolean; const ATypeName, AHelperName,
  AKind: string): TTextEdit;
begin
  Result := TypeDeclaration(ASource, AInTypeSection, [
    cTexts[TTypeCommandsText.OnlyOneHelperPerType].Text,
    Format('%s = %s helper for %s', [AHelperName, AKind, ATypeName]),
    'public', 'end;']);
end;

function ExecuteHelper(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  mSource: TCommandSource;
  mTypeName, mHelperName, mElement: string;
  mInTypeSection: Boolean;
  mValues: TArray<string>;
begin
  AEdits := nil;
  mTypeName := Trim(AContext.Arguments);
  if not IsValidIdent(mTypeName, True) then
  begin
    Exit(Fail(cTexts[TTypeCommandsText.ExpectedIsHelperTType].Text, AReason));
  end;
  mSource := TCommandSource.Create(AContext);
  try
    Result := TypePlace(mSource, 'helper', mInTypeSection, AReason);
    if not Result then
    begin
      Exit;
    end;
    mHelperName := StringReplace(mTypeName, '.', '', [rfReplaceAll]) + 'Helper';
    if IsClassType(mSource, AContext.Index, mTypeName) then
    begin
      AEdits := [PlainHelper(mSource, mInTypeSection, mTypeName, mHelperName, 'class')];
    end
    // #875: Mengen bekommen Contains, ToText, Toggle und All (abschaltbar).
    else if SettingOn(AContext, TSlashSettings.cSetHelper) and SetElement(mSource, AContext, mTypeName, mElement) then
    begin
      AEdits := SetHelper(mSource, AContext, mInTypeSection, mTypeName, mHelperName, mElement);
      if not EnumMembers(mSource, AContext.Index, mElement, mValues) then
      begin
        AddMissingUses(mSource, AContext, 'System.TypInfo', mSource.Line, AEdits);
      end;
    end
    // #875: Aufzählungen bekommen Namen, ToString und FromString (abschaltbar).
    else if SettingOn(AContext, TSlashSettings.cEnumHelper) and
      EnumMembers(mSource, AContext.Index, mTypeName, mValues) then
    begin
      AEdits := EnumHelper(mSource, mInTypeSection, mTypeName, mHelperName, mValues);
      AddMissingUses(mSource, AContext, 'System.SysUtils', mSource.Line, AEdits);
    end
    else
    begin
      AEdits := [PlainHelper(mSource, mInTypeSection, mTypeName, mHelperName, 'record')];
    end;
  finally
    mSource.Free;
  end;
end;

{ Klassenbefehle }

/// <summary>Deklarationen vor "end" der Klasse, Rümpfe hinter ihre letzte Methode.</summary>
function AddToClass(ASource: TCommandSource; const AClass: TIndexSymbol; const ADeclarations: array of string;
  const ABodies: string): TArray<TTextEdit>;
var
  mEndLine, mIndex: Integer;
  mIndent, mText: string;
begin
  mEndLine := AClass.Range.EndPos.Line;
  mIndent := ASource.Indent(mEndLine);
  mText := '';
  for mIndex := 0 to High(ADeclarations) do
  begin
    if mIndex > 0 then
    begin
      mText := mText + ASource.LineBreak;
    end;
    // Abschnittsnamen ohne, Mitglieder mit zusätzlicher Einrückung.
    if MatchText(ADeclarations[mIndex], ['private', 'protected', 'public', 'published', 'strict private']) then
    begin
      mText := mText + mIndent + ADeclarations[mIndex];
    end
    else
    begin
      mText := mText + mIndent + '  ' + ADeclarations[mIndex];
    end;
  end;
  Result := [ASource.BeforeLine(mEndLine, mText)];
  if ABodies <> '' then
  begin
    Result := Result + [ASource.AddBody(AClass.Name, ABodies)];
  end;
end;

function Join(ASource: TCommandSource; const ALines: array of string): string;
var
  mIndex: Integer;
begin
  Result := '';
  for mIndex := 0 to High(ALines) do
  begin
    if mIndex > 0 then
    begin
      Result := Result + ASource.LineBreak;
    end;
    Result := Result + ALines[mIndex];
  end;
end;

/// <summary>Felder von AClass in der Datei.</summary>
function FieldsOf(ASource: TCommandSource; const AClass: TIndexSymbol): TArray<TIndexSymbol>;
var
  mSymbol: TIndexSymbol;
begin
  Result := nil;
  for mSymbol in ASource.UnitIndex.Symbols do
  begin
    if (mSymbol.Kind = TIndexSymbolKind.Field) and SameText(mSymbol.Container, AClass.Name) and
      (mSymbol.TypeName <> '') then
    begin
      Result := Result + [mSymbol];
    end;
  end;
end;

/// <summary>Klasse oder Record um die Befehlszeile.</summary>
function TypeAt(ASource: TCommandSource; const AName: string; out AType: TIndexSymbol;
  out AReason: string): Boolean;
var
  mSymbol: TIndexSymbol;
begin
  if ASource.ClassAt(AType) then
  begin
    Exit(True);
  end;
  for mSymbol in ASource.UnitIndex.Symbols do
  begin
    if (mSymbol.Kind = TIndexSymbolKind.RecordType) and (mSymbol.Range.StartPos.Line < ASource.Line) and
      (mSymbol.Range.EndPos.Line > ASource.Line) then
    begin
      AType := mSymbol;
      Exit(True);
    end;
  end;
  Result := Fail(cTexts[TTypeCommandsText.OnlyAppliesInAClass].Fmt([AName]), AReason);
end;

{ /singleton }

/// <summary>Hinweis nach /singleton, wenn die Klasse schon Konstruktoren hat (#298); '' ohne.</summary>
function SingletonConstructorNote(ASource: TCommandSource; const AClassName: string): string;
var
  mSymbol: TIndexSymbol;
  mNames: TArray<string>;
begin
  mNames := nil;
  for mSymbol in ASource.UnitIndex.Symbols do
  begin
    if (mSymbol.Kind = TIndexSymbolKind.Constructor_) and SameText(mSymbol.Container, AClassName) and
      not MatchText(mSymbol.Name, mNames) then
    begin
      mNames := mNames + [mSymbol.Name];
    end;
  end;
  Result := '';
  if mNames <> nil then
  begin
    Result := cTexts[TTypeCommandsText.SingletonConstructorStaysUnchangedAnd].Fmt([string.Join(', ', mNames)]);
  end;
end;

function ExecuteSingleton(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>;
  out AReason: string): Boolean;
var
  mSource: TCommandSource;
  mClassSymbol: TIndexSymbol;
  mName, mNote, mUri: string;
  mHost: ISlashHost;
begin
  AEdits := nil;
  mSource := TCommandSource.Create(AContext);
  try
    if not mSource.ClassAt(mClassSymbol) then
    begin
      Exit(Fail(cTexts[TTypeCommandsText.SingletonOnlyAppliesInA].Text, AReason));
    end;
    mName := mClassSymbol.Name;
    AEdits := AddToClass(mSource, mClassSymbol, ['private', Format('class var FInstance: %s;', [mName]), 'public',
      'class destructor Destroy;', Format('class function Instance: %s;', [mName])],
      Join(mSource, [Format('class destructor %s.Destroy;', [mName]), 'begin', '  FreeAndNil(FInstance);', 'end;',
      '', Format('class function %s.Instance: %s;', [mName, mName]), 'begin', '  if FInstance = nil then',
      Format('    FInstance := %s.Create;', [mName]), '  Result := FInstance;', 'end;'])) + [mSource.RemoveCommand];
    // Ein vorhandener Konstruktor bleibt, wie er ist; der Hinweis nennt ihn.
    mNote := SingletonConstructorNote(mSource, mName);
    mHost := AContext.Host;
    mUri := AContext.Uri;
    if (mHost <> nil) and (mNote <> '') then
    begin
      AContext.Defer(
        procedure
        begin
          mHost.Notify(mUri, mNote);
        end);
    end;
    Result := True;
  finally
    mSource.Free;
  end;
end;

{ /encapsulate }

/// <summary>Ein Feldname mit F-Präfix: FName, nicht Farbe.</summary>
function HasFieldPrefix(const AName: string): Boolean;
begin
  Result := (Length(AName) >= 2) and CharInSet(AName[1], ['F', 'f']) and CharInSet(AName[2], ['A'..'Z']);
end;

/// <summary>Bereiche der Methodenrümpfe von AClassName.</summary>
function MethodRanges(ASource: TCommandSource; const AClassName: string): TArray<TTextRange>;
var
  mPrefix: string;
  mFound: TList<TTextRange>;
begin
  mPrefix := AClassName + '.';
  // Walk statt Rekursion (Bericht M1); in die gefundenen Methoden geht der Lauf nicht hinein.
  mFound := TList<TTextRange>.Create;
  try
    ASource.Tree.Root.Walk(
      function(AChild: TSyntaxNode): Boolean
      begin
        Result := not ((AChild.Kind = TSyntaxKind.RoutineDecl) and StartsText(mPrefix, AChild.Name));
        if not Result then
        begin
          mFound.Add(TTextRange.Create(AChild.StartPos, AChild.EndPos));
        end;
      end);
    Result := mFound.ToArray;
  finally
    mFound.Free;
  end;
end;

/// <summary>Liegt Zeile ALine hinter der Kopfzeile eines der Bereiche ARanges?</summary>
function InMethodBody(ALine: Integer; const ARanges: TArray<TTextRange>): Boolean;
var
  mRange: TTextRange;
begin
  for mRange in ARanges do
  begin
    if (ALine > mRange.StartPos.Line) and (ALine <= mRange.EndPos.Line) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Letztes Token ab AIndex rückwärts, das weder Kommentar noch Direktive ist; -1 ohne.</summary>
function SolidBefore(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
begin
  Result := AIndex;
  while (Result >= 0) and (ATokens[Result].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) do
  begin
    Dec(Result);
  end;
end;

/// <summary>Steht das Token AIndex allein oder hinter "Self." (nicht hinter einem anderen Ausdruck mit Punkt)?
/// </summary>
function IsOwnAccess(const ATokens: TArray<TPascalToken>; AIndex: Integer): Boolean;
var
  mBefore: Integer;
begin
  mBefore := SolidBefore(ATokens, AIndex - 1);
  if (mBefore < 0) or not ATokens[mBefore].IsSymbol('.') then
  begin
    Exit(True);
  end;
  mBefore := SolidBefore(ATokens, mBefore - 1);
  Result := (mBefore >= 0) and SameText(ATokens[mBefore].Text, 'Self');
end;

/// <summary>Benennt in den Methodenrümpfen von AClassName das Feld AOld in ANew um: der Name allein
/// oder hinter "Self.", nicht hinter einem anderen Ausdruck mit Punkt.</summary>
function RenameInMethods(ASource: TCommandSource; const AClassName, AOld, ANew: string): TArray<TTextEdit>;
var
  mTokens: TArray<TPascalToken>;
  mRanges: TArray<TTextRange>;
  mIndex: Integer;
begin
  Result := nil;
  mRanges := MethodRanges(ASource, AClassName);
  mTokens := TPascalLexer.Tokenize(ASource.Text);
  for mIndex := 0 to High(mTokens) do
  begin
    if (mTokens[mIndex].Kind = TPascalTokenKind.Identifier) and SameText(mTokens[mIndex].Text, AOld) and
      InMethodBody(mTokens[mIndex].StartPos.Line, mRanges) and IsOwnAccess(mTokens, mIndex) then
    begin
      Result := Result + [TTextEdit.Create(TTextRange.Create(mTokens[mIndex].StartPos, mTokens[mIndex].EndPos),
        ANew)];
    end;
  end;
end;

/// <summary>Namen für /encapsulate: Property AName und Feld AFieldName; True, wenn das Feld dabei umbenannt wird
/// (ohne F-Präfix, #298).</summary>
function EncapsulateNames(const AOldName: string; out AName, AFieldName: string): Boolean;
begin
  Result := not HasFieldPrefix(AOldName);
  if Result then
  begin
    AName := AOldName;
    AFieldName := 'F' + UpperCase(Copy(AOldName, 1, 1)) + Copy(AOldName, 2, MaxInt);
  end
  else
  begin
    AName := Copy(AOldName, 2, MaxInt);
    AFieldName := AOldName;
  end;
end;

/// <summary>Sucht das Feld AOldName in AClass; Grund, wenn es fehlt oder der neue Name AFieldName beim Umbenennen
/// (ARename) schon vergeben ist, sonst ''.</summary>
function FindField(ASource: TCommandSource; const AClass: TIndexSymbol; const AOldName, AFieldName: string;
  ARename: Boolean; out AField: TIndexSymbol): string;
var
  mSymbol: TIndexSymbol;
begin
  AField := Default(TIndexSymbol);
  Result := cTexts[TTypeCommandsText.NoFieldIn].Fmt([AOldName]) + AClass.Name;
  for mSymbol in FieldsOf(ASource, AClass) do
  begin
    if ARename and SameText(mSymbol.Name, AFieldName) then
    begin
      Exit(cTexts[TTypeCommandsText.AlreadyExistsIn].Fmt([AFieldName, AClass.Name]));
    end;
    if SameText(mSymbol.Name, AOldName) then
    begin
      AField := mSymbol;
      Result := '';
    end;
  end;
end;

/// <summary>Grund, wenn AField schon private ist oder nicht allein in seiner Zeile steht ("FName: string;");
/// sonst ''.</summary>
function FieldPlacementIssue(ASource: TCommandSource; const AField: TIndexSymbol; const AOldName: string): string;
var
  mLine: string;
begin
  mLine := ASource.Lines[AField.Range.StartPos.Line];
  Result := '';
  if AField.Visibility in [TIndexVisibility.Private, TIndexVisibility.StrictPrivate] then
  begin
    Result := AOldName + cTexts[TTypeCommandsText.IsAlreadyPrivate].Text;
  end
  else if (AField.Range.StartPos.Line <> AField.Range.EndPos.Line) or
    not StartsText(AOldName + ':', StringReplace(Trim(mLine), ' :', ':', [])) or (Pos(',', mLine) > 0) then
  begin
    Result := AOldName + cTexts[TTypeCommandsText.MustBeDeclaredAloneOn].Text;
  end;
end;

/// <summary>Neues privates Feld AFieldName, Setter und Property AName in AClass; die alte Deklaration und die
/// Befehlszeile gehen.</summary>
function EncapsulateEdits(ASource: TCommandSource; const AIndex: ISymbolIndex; const AClass, AField: TIndexSymbol;
  const AName, AFieldName: string): TArray<TTextEdit>;
begin
  Result := AddToClass(ASource, AClass, ['private', Format('%s: %s;', [AFieldName, AField.TypeName]),
    Format('procedure Set%s(const Value: %s);', [AName, AField.TypeName]), 'public',
    Format('property %s: %s read %s write Set%s;', [AName, AField.TypeName, AFieldName, AName])],
    Join(ASource, [Format('procedure %s.Set%s(const Value: %s);', [AClass.Name, AName, AField.TypeName]),
    TSetterGenerator.Body(AFieldName, 'Value', TSetterGenerator.NotifyCall(ASource, AIndex, AClass),
    ASource.LineBreak)]));
  // Alte Deklaration entfernen.
  Result := Result + [TTextEdit.Create(TTextRange.Create(AField.Range.StartPos.Line, 0,
    AField.Range.StartPos.Line + 1, 0), ''), ASource.RemoveCommand];
end;

function ExecuteEncapsulate(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>;
  out AReason: string): Boolean;
var
  mSource: TCommandSource;
  mClass, mField: TIndexSymbol;
  mName, mFieldName, mOldName: string;
  mRename: Boolean;
begin
  AEdits := nil;
  mOldName := Trim(AContext.Arguments);
  if not IsValidIdent(mOldName) then
  begin
    Exit(Fail(cTexts[TTypeCommandsText.ExpectedIsEncapsulateFName].Text, AReason));
  end;
  // Ohne F-Präfix (#298): das Feld heißt danach FName, die Property trägt den alten Namen, damit
  // Verwendungen außerhalb der Klasse gültig bleiben; in den eigenen Methoden wird es umbenannt.
  mRename := EncapsulateNames(mOldName, mName, mFieldName);
  mSource := TCommandSource.Create(AContext);
  try
    AReason := cTexts[TTypeCommandsText.EncapsulateOnlyAppliesInA].Text;
    if mSource.ClassAt(mClass) then
    begin
      AReason := FindField(mSource, mClass, mOldName, mFieldName, mRename, mField);
    end;
    if AReason = '' then
    begin
      AReason := FieldPlacementIssue(mSource, mField, mOldName);
    end;
    Result := AReason = '';
    if Result then
    begin
      AEdits := EncapsulateEdits(mSource, AContext.Index, mClass, mField, mName, mFieldName);
      if mRename then
      begin
        AEdits := AEdits + RenameInMethods(mSource, mClass.Name, mOldName, mFieldName);
      end;
    end;
  finally
    mSource.Free;
  end;
end;

{ /assign }

function IsObjectField(ASource: TCommandSource; const AIndex: ISymbolIndex; const AField: TIndexSymbol): Boolean;
begin
  Result := not MatchText(AField.TypeName, cStringTypes) and not MatchText(AField.TypeName, cIntegerTypes) and
    not MatchText(AField.TypeName, cFloatTypes) and not SameText(AField.TypeName, 'Boolean') and
    IsClassType(ASource, AIndex, AField.TypeName);
end;

function ExecuteAssign(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  mSource: TCommandSource;
  mClassSymbol, mField: TIndexSymbol;
  mName, mBody: string;
begin
  AEdits := nil;
  mSource := TCommandSource.Create(AContext);
  try
    if not mSource.ClassAt(mClassSymbol) then
    begin
      Exit(Fail(cTexts[TTypeCommandsText.AssignOnlyAppliesInA].Text, AReason));
    end;
    mName := mClassSymbol.Name;
    mBody := Join(mSource, [Format('procedure %s.Assign(Source: TPersistent);', [mName]), 'begin',
      Format('  if Source is %s then', [mName]), '  begin']);
    for mField in FieldsOf(mSource, mClassSymbol) do
    begin
      if IsObjectField(mSource, AContext.Index, mField) then
      begin
        mBody := mBody + mSource.LineBreak + Format('    %s.Assign(%s(Source).%s);', [mField.Name, mName, mField.Name]);
      end
      else
      begin
        mBody := mBody + mSource.LineBreak + Format('    %s := %s(Source).%s;', [mField.Name, mName, mField.Name]);
      end;
    end;
    mBody := mBody + mSource.LineBreak + Join(mSource, ['  end', '  else', '    inherited Assign(Source);', 'end;']);
    AEdits := AddToClass(mSource, mClassSymbol, ['public', 'procedure Assign(Source: TPersistent); override;'], mBody) +
      [mSource.RemoveCommand];
    Result := True;
  finally
    mSource.Free;
  end;
end;

{ /json }

/// <summary>JSON-Schlüssel zum Feld AFieldName: ohne F-Präfix.</summary>
function JsonKey(const AFieldName: string): string;
begin
  Result := AFieldName;
  if StartsText('F', Result) and (Length(Result) > 1) and CharInSet(Result[2], ['A'..'Z']) then
  begin
    Result := Copy(Result, 2, MaxInt);
  end;
end;

/// <summary>Hängt Schreiben und Lesen des Felds AField an AToJson und AFromJson an; unbekannte Typen als TODO.
/// </summary>
procedure AddJsonField(const AField: TIndexSymbol; const ALineBreak: string; var AToJson, AFromJson: string);
var
  mKey: string;
begin
  mKey := JsonKey(AField.Name);
  if MatchText(AField.TypeName, cStringTypes) then
  begin
    AToJson := AToJson + ALineBreak + Format('  Result.AddPair(''%s'', %s);', [mKey, AField.Name]);
    AFromJson := AFromJson + ALineBreak + Format('  Result.%s := AJson.GetValue<string>(''%s'');', [AField.Name,
      mKey]);
  end
  else if MatchText(AField.TypeName, cIntegerTypes) or MatchText(AField.TypeName, cFloatTypes) then
  begin
    AToJson := AToJson + ALineBreak + Format('  Result.AddPair(''%s'', TJSONNumber.Create(%s));', [mKey,
      AField.Name]);
    AFromJson := AFromJson + ALineBreak + Format('  Result.%s := AJson.GetValue<%s>(''%s'');', [AField.Name,
      AField.TypeName, mKey]);
  end
  else if SameText(AField.TypeName, 'Boolean') then
  begin
    AToJson := AToJson + ALineBreak + Format('  Result.AddPair(''%s'', TJSONBool.Create(%s));', [mKey,
      AField.Name]);
    AFromJson := AFromJson + ALineBreak + Format('  Result.%s := AJson.GetValue<Boolean>(''%s'');', [AField.Name,
      mKey]);
  end
  else
  begin
    AToJson := AToJson + ALineBreak + Format('  // TODO %s: %s', [AField.Name, AField.TypeName]);
    AFromJson := AFromJson + ALineBreak + Format('  // TODO %s: %s', [AField.Name, AField.TypeName]);
  end;
end;

/// <summary>Rümpfe von ToJson und FromJson für den Typ ATypeSymbol (Klasse oder Record).</summary>
function JsonBodies(ASource: TCommandSource; const ATypeSymbol: TIndexSymbol): string;
var
  mName, mToJson, mFromJson: string;
  mField: TIndexSymbol;
begin
  mName := ATypeSymbol.Name;
  mToJson := Join(ASource, [Format('function %s.ToJson: TJSONObject;', [mName]), 'begin',
    '  Result := TJSONObject.Create;']);
  mFromJson := Join(ASource, [Format('class function %s.FromJson(AJson: TJSONObject): %s;', [mName, mName]),
    'begin']);
  if ATypeSymbol.Kind = TIndexSymbolKind.ClassType then
  begin
    mFromJson := mFromJson + ASource.LineBreak + Format('  Result := %s.Create;', [mName]);
  end
  else
  begin
    mFromJson := mFromJson + ASource.LineBreak + Format('  Result := Default(%s);', [mName]);
  end;
  for mField in FieldsOf(ASource, ATypeSymbol) do
  begin
    AddJsonField(mField, ASource.LineBreak, mToJson, mFromJson);
  end;
  Result := mToJson + ASource.LineBreak + 'end;' + ASource.LineBreak + ASource.LineBreak + mFromJson +
    ASource.LineBreak + 'end;';
end;

function ExecuteJson(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  mSource: TCommandSource;
  mTypeSymbol: TIndexSymbol;
begin
  AEdits := nil;
  mSource := TCommandSource.Create(AContext);
  try
    Result := TypeAt(mSource, 'json', mTypeSymbol, AReason);
    if Result then
    begin
      AEdits := AddToClass(mSource, mTypeSymbol, ['public', 'function ToJson: TJSONObject;',
        Format('class function FromJson(AJson: TJSONObject): %s; static;', [mTypeSymbol.Name])],
        JsonBodies(mSource, mTypeSymbol)) + [mSource.RemoveCommand];
      AddMissingUses(mSource, AContext, 'System.JSON', mTypeSymbol.Range.StartPos.Line, AEdits);
    end;
  finally
    mSource.Free;
  end;
end;

{ /exception }

function ExecuteException(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>;
  out AReason: string): Boolean;
var
  mSource: TCommandSource;
  mName, mAncestor: string;
  mInTypeSection: Boolean;
begin
  AEdits := nil;
  if Pos(':', AContext.Arguments) > 0 then
  begin
    mName := Trim(Copy(AContext.Arguments, 1, Pos(':', AContext.Arguments) - 1));
    mAncestor := Trim(Copy(AContext.Arguments, Pos(':', AContext.Arguments) + 1, MaxInt));
  end
  else
  begin
    mName := Trim(AContext.Arguments);
    mAncestor := 'Exception';
  end;
  if not IsValidIdent(mName) or not IsValidIdent(mAncestor, True) then
  begin
    Exit(Fail(cTexts[TTypeCommandsText.ExpectedIsExceptionENameEBase].Text, AReason));
  end;
  mSource := TCommandSource.Create(AContext);
  try
    if not TypePlace(mSource, 'exception', mInTypeSection, AReason) then
    begin
      Exit(False);
    end;
    AEdits := [TypeDeclaration(mSource, mInTypeSection, [Format('%s = class(%s);', [mName, mAncestor])])];
    Result := True;
  finally
    mSource.Free;
  end;
end;

{ /thread }

function ExecuteThread(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  mSource: TCommandSource;
  mTypeName: string;
  mInTypeSection: Boolean;
begin
  AEdits := nil;
  mTypeName := Trim(AContext.Arguments);
  if not IsValidIdent(mTypeName) then
  begin
    Exit(Fail(cTexts[TTypeCommandsText.ExpectedIsThreadTName].Text, AReason));
  end;
  mSource := TCommandSource.Create(AContext);
  try
    if not TypePlace(mSource, 'thread', mInTypeSection, AReason) then
    begin
      Exit(False);
    end;
    AEdits := [TypeDeclaration(mSource, mInTypeSection, [Format('%s = class(TThread)', [mTypeName]), 'protected',
      '  procedure Execute; override;', 'end;']), mSource.AddBody(mTypeName, Join(mSource, [
      Format('procedure %s.Execute;', [mTypeName]), 'begin',
      cTexts[TTypeCommandsText.IfNobodyWaitsForThe].Text,
      '  while not Terminated do', '  begin',
      cTexts[TTypeCommandsText.ShowResultsInTheMain].Text, '  end;', 'end;']))];
    AddMissingUses(mSource, AContext, 'System.Classes', mSource.Line, AEdits);
    Result := True;
  finally
    mSource.Free;
  end;
end;

function Command(const AName, ASummary, AExample: string; const AExecute: TSlashExecute): TSlashCommand;
begin
  Result.Name := AName;
  Result.Summary := ASummary;
  Result.Example := AExample;
  Result.Execute := AExecute;
end;

procedure RegisterTypeCommands(const ARegister: TSlashRegister);
begin
  ARegister(Command('enum', cTexts[TTypeCommandsText.CreateAnEnumerationTypeWith].Text,
    cTexts[TTypeCommandsText.EnumTColorRedGreenBlue].Text,
    function(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean
    begin
      Result := ExecuteEnum(AContext, True, AEdits, AReason);
    end));
  ARegister(Command('enum!', cTexts[TTypeCommandsText.CreateAnEnumerationTypeWithout].Text,
    cTexts[TTypeCommandsText.EnumTColorRedGreen].Text,
    function(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean
    begin
      Result := ExecuteEnum(AContext, False, AEdits, AReason);
    end));
  ARegister(Command('helper', cTexts[TTypeCommandsText.CreateARecordOrClass].Text,
    cTexts[TTypeCommandsText.HelperTColor].Text, ExecuteHelper));
  ARegister(Command('singleton', cTexts[TTypeCommandsText.MakeTheClassASingleton].Text, '/singleton',
    ExecuteSingleton));
  ARegister(Command('encapsulate', cTexts[TTypeCommandsText.ConvertAFieldIntoA].Text, '/encapsulate FName',
    ExecuteEncapsulate));
  ARegister(Command('assign', cTexts[TTypeCommandsText.CreateAssignForAllFields].Text, '/assign', ExecuteAssign));
  ARegister(Command('json', cTexts[TTypeCommandsText.CreateToJsonAndFromJson].Text, '/json', ExecuteJson));
  ARegister(Command('exception', cTexts[TTypeCommandsText.CreateAnExceptionClass].Text,
    cTexts[TTypeCommandsText.ExceptionEImportError].Text,
    ExecuteException));
  ARegister(Command('thread', cTexts[TTypeCommandsText.CreateATThreadDescendantWith].Text, '/thread TWorker',
    ExecuteThread));
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Editing.TypeCommands', cTexts);

end.
