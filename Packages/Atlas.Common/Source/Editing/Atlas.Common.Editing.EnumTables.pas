unit Atlas.Common.Editing.EnumTables;

// Aufzählung mit Namenstabelle (#667):
//   - Target und CreateTable: auf einem Aufzählungstyp ohne feste Werte die
//     Konstante "CTypNames: array[TTyp] of string = ('New', 'Payment due')"
//     direkt hinter der Typdeklaration oder im implementation-Teil; die Texte
//     aus den Elementnamen (gemeinsames Kleinbuchstaben-Präfix weg,
//     CamelCase getrennt), wahlweise je Element ein resourcestring und eine
//     Tabelle mit @-Verweisen (PResStringRec, LoadResString).
//   - Tables und TableAt: typisierte Konstanten und initialisierte Variablen
//     "array[TTyp] of …" mit Klammerwert.
//   - Repair: bringt einen Klammerwert auf die Elemente des Typs. Welcher
//     Eintrag zu welchem Element gehört, verraten Texte (gleich dem
//     Elementnamen oder seinem Text), Bezeichner (@SOrderStatePaid) und
//     Kommentare mit dem Elementnamen ({osPaid}, // osPaid); dazwischen zählt
//     die Reihenfolge. Fehlende Einträge kommen an ihre Stelle, überzählige
//     fallen weg; reicht das nicht für eine sichere Stelle, ist das Ergebnis
//     als geschätzt markiert.
//   - Neue Einträge: bei Strings der Text aus dem Namen, bei resourcestring-
//     Tabellen ein neuer resourcestring, sonst der Standardwert des
//     Elementtyps bzw. eine Kopie des Nachbarn, jeweils mit {TODO Element}.

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree;

type
  /// <summary>Wo die neue Tabelle steht.</summary>
  TEnumTablePlacement = (AfterType, InImplementation);

  /// <summary>Name, Ort und Art der neuen Tabelle.</summary>
  TEnumTableRequest = record
    Name: string;
    Placement: TEnumTablePlacement;
    /// <summary>Texte als resourcestrings, die Tabelle als array of PResStringRec.</summary>
    ResourceStrings: Boolean;
    class function Create(const AName: string; APlacement: TEnumTablePlacement;
      AResourceStrings: Boolean): TEnumTableRequest; static;
  end;

  /// <summary>Art des Elementtyps einer Tabelle, für den Wert neuer Einträge.</summary>
  TEnumTableElement = (Text, Number, Float, Boolean_, Char_, Pointer_, Enum, ResourceString_, Other);

  /// <summary>Ein Aufzählungstyp, für den eine Namenstabelle angelegt werden kann.</summary>
  TEnumTarget = record
    TypeName: string;
    Names: TArray<string>;
    NamePosition: TTextPosition;
    InInterface: Boolean;
  end;

  /// <summary>Eine Tabelle array[TTyp] of … = (…).</summary>
  TEnumTable = record
    /// <summary>ConstDecl bzw. VarDecl.</summary>
    Decl: TSyntaxNode;
    /// <summary>TypeReference des Index.</summary>
    IndexType: TSyntaxNode;
    /// <summary>Typ der Elemente.</summary>
    ElementType: TSyntaxNode;
    /// <summary>ParenExpr mit den Einträgen.</summary>
    Value: TSyntaxNode;
  end;

  /// <summary>Wie neue Einträge aussehen.</summary>
  TEnumTableValues = record
    Element: TEnumTableElement;
    /// <summary>Elementtyp wie im Quelltext (für Low(TTyp)).</summary>
    ElementType: string;
    /// <summary>Indextyp, für die Namen neuer resourcestrings.</summary>
    IndexType: string;
    class function Create(AElement: TEnumTableElement; const AElementType, AIndexType: string): TEnumTableValues;
      static;
  end;

  TEnumTableRepair = record
    Edits: TArray<TTextEdit>;
    /// <summary>Ergänzte Elemente.</summary>
    Added: TArray<string>;
    /// <summary>Entfernte Einträge wie im Quelltext.</summary>
    Removed: TArray<string>;
    /// <summary>Die Stelle ist geschätzt: Einträge ohne Hinweis auf ihr Element.</summary>
    Uncertain: Boolean;
    /// <summary>Titel der Code-Aktion.</summary>
    function Title: string;
  end;

  TEnumTables = class
  public
    class function CreateTitle: string; static;
    class function CreateImplementationTitle: string; static;
    class function SyncTitle: string; static;
    class function AddTitle: string; static;
    class function AddManyTitle: string; static;
    class function RemoveTitle: string; static;
    class function RemoveManyTitle: string; static;
    class function AdjustTitle: string; static;
    class function UncertainSuffix: string; static;
    class function UncertainNote: string; static;
    /// <summary>Gemeinsames Präfix aus Kleinbuchstaben aller Namen (os bei osNew, osPaid); '' ohne.</summary>
    class function CommonPrefix(const ANames: TArray<string>): string; static;
    /// <summary>Text eines Elements: APrefix weg, CamelCase getrennt: osPaymentDue → Payment due.</summary>
    class function DisplayText(const AName, APrefix: string): string; static;
    /// <summary>Vorgeschlagener Name der Tabelle: C + Typname ohne T + Names.</summary>
    class function TableName(const ATypeName: string): string; static;
    /// <summary>Name des resourcestring je Element: S + Typname ohne T + Element ohne Präfix.</summary>
    class function ResourceName(const ATypeName, AName, APrefix: string): string; static;
    /// <summary>Aufzählungstyp, in dessen Deklaration APosition liegt.</summary>
    class function Target(ATree: TSyntaxTree; const APosition: TTextPosition; out ATarget: TEnumTarget;
      out AReason: string): Boolean; static;
    /// <summary>Änderungen für die Tabelle nach ARequest; False mit Grund.</summary>
    class function CreateTable(const AText: string; ATree: TSyntaxTree; const APosition: TTextPosition;
      const ARequest: TEnumTableRequest; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean; static;
    /// <summary>Alle Tabellen der Datei.</summary>
    class function Tables(ATree: TSyntaxTree): TArray<TEnumTable>; static;
    /// <summary>Tabelle, in deren Deklaration APosition liegt.</summary>
    class function TableAt(ATree: TSyntaxTree; const APosition: TTextPosition; out ATable: TEnumTable): Boolean;
      static;
    /// <summary>Art eines Elementtyps nach seinem Namen; Other, wenn der Name allein es nicht sagt.</summary>
    class function ElementOf(const ATypeName: string): TEnumTableElement; static;
    /// <summary>Bringt den Klammerwert AValue auf ANames; False, wenn nichts fehlt und nichts zu viel ist oder
    /// es nicht geht. ATree für resourcestring-Tabellen (neuer Eintrag im Abschnitt des Nachbarn).</summary>
    class function Repair(const AText: string; ATree: TSyntaxTree; AValue: TSyntaxNode; const ANames: TArray<string>;
      const AValues: TEnumTableValues; out ARepair: TEnumTableRepair): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Character,
  Atlas.Text.Lines,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Editing.ResourceStrings,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TEditingEnumTablesText = (NoEnumerationTypeAtThis, IsNotDirectlyInThe, HasElementsWithFixedValues, IsNotAValidName,
    TheNameIsAlreadyTaken, TheUnitHasNoImplementation, CreateNameTable, CreateNameTableInThe, UpdateTablesOf,
    AddMissingEntry, AddMissingEntries, RemoveSurplusEntry, RemoveSurplusEntries, AdjustTableTo, PositionEstimated,
    ThePositionIsEstimatedNot);

const
  cTexts: array[TEditingEnumTablesText] of TAtlasText = (
    (De: 'Kein Aufzählungstyp an dieser Stelle'; En: 'No enumeration type at this position'),
    (De: '%s steht nicht direkt im interface- oder implementation-Teil';
     En: '%s is not directly in the interface or implementation part'),
    (De: '%s hat Elemente mit festen Werten; eine Tabelle darüber hätte Lücken';
     En: '%s has elements with fixed values; a table over it would have gaps'),
    (De: '%s ist kein gültiger Name'; En: '%s is not a valid name'),
    (De: 'Der Name %s ist schon vergeben'; En: 'The name %s is already taken'),
    (De: 'Die Unit hat keinen implementation-Teil'; En: 'The unit has no implementation part'),
    (De: 'Namenstabelle anlegen (%s)'; En: 'Create name table (%s)'),
    (De: 'Namenstabelle anlegen, im implementation-Teil (%s)';
     En: 'Create name table, in the implementation part (%s)'),
    (De: 'Tabellen von %s nachziehen'; En: 'Update tables of %s'),
    (De: 'Fehlenden Eintrag ergänzen (%s)'; En: 'Add missing entry (%s)'),
    (De: 'Fehlende Einträge ergänzen (%s)'; En: 'Add missing entries (%s)'),
    (De: 'Überzähligen Eintrag entfernen (%s)'; En: 'Remove surplus entry (%s)'),
    (De: 'Überzählige Einträge entfernen (%d)'; En: 'Remove surplus entries (%d)'),
    (De: 'Tabelle an %s anpassen'; En: 'Adjust table to %s'),
    (De: ', Stelle geschätzt'; En: ', position estimated'),
    (De: 'Die Stelle ist geschätzt: Nicht jeder Eintrag lässt sich einem Element zuordnen; Kommentare wie {osPaid} ' +
      'machen sie sicher.';
     En: 'The position is estimated: not every entry can be assigned to an element; comments like {osPaid} make it ' +
      'certain.'));

{$SCOPEDENUMS OFF}

class function TEnumTables.CreateTitle: string;
begin
  Result := cTexts[TEditingEnumTablesText.CreateNameTable].Text;
end;

class function TEnumTables.CreateImplementationTitle: string;
begin
  Result := cTexts[TEditingEnumTablesText.CreateNameTableInThe].Text;
end;

class function TEnumTables.SyncTitle: string;
begin
  Result := cTexts[TEditingEnumTablesText.UpdateTablesOf].Text;
end;

class function TEnumTables.AddTitle: string;
begin
  Result := cTexts[TEditingEnumTablesText.AddMissingEntry].Text;
end;

class function TEnumTables.AddManyTitle: string;
begin
  Result := cTexts[TEditingEnumTablesText.AddMissingEntries].Text;
end;

class function TEnumTables.RemoveTitle: string;
begin
  Result := cTexts[TEditingEnumTablesText.RemoveSurplusEntry].Text;
end;

class function TEnumTables.RemoveManyTitle: string;
begin
  Result := cTexts[TEditingEnumTablesText.RemoveSurplusEntries].Text;
end;

class function TEnumTables.AdjustTitle: string;
begin
  Result := cTexts[TEditingEnumTablesText.AdjustTableTo].Text;
end;

class function TEnumTables.UncertainSuffix: string;
begin
  Result := cTexts[TEditingEnumTablesText.PositionEstimated].Text;
end;

class function TEnumTables.UncertainNote: string;
begin
  Result := cTexts[TEditingEnumTablesText.ThePositionIsEstimatedNot].Text;
end;

const
  /// <summary>Ab dieser Länge steht die neue Tabelle je Eintrag auf einer Zeile.</summary>
  LineLimit = 110;

function Fail(const AMessage: string; out AReason: string): Boolean;
begin
  AReason := AMessage;
  Result := False;
end;

function Bare(const ATypeName: string): string;
begin
  Result := ATypeName;
  if (Length(Result) > 1) and (Result[1] = 'T') and Result[2].IsUpper then
  begin
    Delete(Result, 1, 1);
  end;
end;

{ TEnumTableRequest }

class function TEnumTableRequest.Create(const AName: string; APlacement: TEnumTablePlacement;
  AResourceStrings: Boolean): TEnumTableRequest;
begin
  Result.Name := AName;
  Result.Placement := APlacement;
  Result.ResourceStrings := AResourceStrings;
end;

{ TEnumTableValues }

class function TEnumTableValues.Create(AElement: TEnumTableElement; const AElementType,
  AIndexType: string): TEnumTableValues;
begin
  Result.Element := AElement;
  Result.ElementType := AElementType;
  Result.IndexType := AIndexType;
end;

{ TEnumTableRepair }

function TEnumTableRepair.Title: string;
begin
  if (Added <> nil) and (Removed <> nil) then
  begin
    Result := Format(TEnumTables.AdjustTitle, [string.Join(', ', Added)]);
  end
  else if Length(Added) = 1 then
  begin
    Result := Format(TEnumTables.AddTitle, [Added[0]]);
  end
  else if Added <> nil then
  begin
    Result := Format(TEnumTables.AddManyTitle, [string.Join(', ', Added)]);
  end
  else if Length(Removed) = 1 then
  begin
    Result := Format(TEnumTables.RemoveTitle, [Removed[0]]);
  end
  else
  begin
    Result := Format(TEnumTables.RemoveManyTitle, [Length(Removed)]);
  end;
  if Uncertain then
  begin
    Result := Result + TEnumTables.UncertainSuffix;
  end;
end;

{ TEnumTables }

class function TEnumTables.CommonPrefix(const ANames: TArray<string>): string;
var
  Name: string;
  Length_, Index: Integer;
begin
  Result := '';
  if ANames = nil then
  begin
    Exit;
  end;
  // Kleinbuchstaben am Anfang des ersten Namens, dann kürzen, bis alle passen.
  Length_ := 0;
  while (Length_ < Length(ANames[0])) and ANames[0][Length_ + 1].IsLower do
  begin
    Inc(Length_);
  end;
  for Name in ANames do
  begin
    Index := 0;
    while (Index < Length_) and (Index < Length(Name)) and (Name[Index + 1] = ANames[0][Index + 1]) do
    begin
      Inc(Index);
    end;
    Length_ := Index;
  end;
  // Nach dem Präfix muss in jedem Namen noch etwas Großes folgen (osNew, nicht open/other).
  for Name in ANames do
  begin
    if (Length(Name) <= Length_) or not (Name[Length_ + 1].IsUpper or Name[Length_ + 1].IsDigit) then
    begin
      Exit;
    end;
  end;
  Result := Copy(ANames[0], 1, Length_);
end;

/// <summary>Großbuchstabe an AAt nach Großbuchstaben, vor einem Kleinbuchstaben (HTTPError: E).</summary>
function IsAcronymEnd(const AText: string; AAt: Integer): Boolean;
begin
  Result := AText[AAt - 1].IsUpper and (AAt < Length(AText)) and AText[AAt + 1].IsLower;
end;

/// <summary>Wortgrenze vor AAt: klein → groß, oder groß → groß+klein (HTTPError → HTTP Error).</summary>
function IsWordBreak(const AText: string; AAt: Integer): Boolean;
begin
  Result := AText[AAt].IsUpper and (AText[AAt - 1].IsLower or AText[AAt - 1].IsDigit or IsAcronymEnd(AText, AAt));
end;

/// <summary>AText an Leerzeichen und CamelCase-Grenzen getrennt (Teile können Leerzeichen enthalten).</summary>
function CamelWords(const AText: string): TArray<string>;
var
  mIndex, mStart: Integer;
begin
  Result := nil;
  mStart := 1;
  for mIndex := 2 to Length(AText) do
  begin
    if (AText[mIndex] <> ' ') and (AText[mIndex - 1] <> ' ') and IsWordBreak(AText, mIndex) then
    begin
      Result := Result + [Copy(AText, mStart, mIndex - mStart)];
      mStart := mIndex;
    end;
  end;
  Result := Result + [Copy(AText, mStart, MaxInt)];
end;

/// <summary>Abkürzungen (HTTP) bleiben groß, sonst nur das erste Wort mit großem Anfang.</summary>
function WordCase(const AWord: string; AFirst: Boolean): string;
begin
  Result := AWord;
  if (Length(AWord) > 1) and (UpperCase(AWord) = AWord) then
  begin
    Exit;
  end;
  if AFirst then
  begin
    Result := UpperCase(Copy(AWord, 1, 1)) + LowerCase(Copy(AWord, 2, MaxInt));
  end
  else
  begin
    Result := LowerCase(AWord);
  end;
end;

class function TEnumTables.DisplayText(const AName, APrefix: string): string;
var
  mRest, mWord, mText: string;
begin
  mRest := AName;
  if (APrefix <> '') and StartsStr(APrefix, mRest) then
  begin
    Delete(mRest, 1, Length(APrefix));
  end;
  Result := '';
  for mWord in CamelWords(StringReplace(mRest, '_', ' ', [rfReplaceAll])) do
  begin
    mText := Trim(mWord);
    if mText = '' then
    begin
      Continue;
    end;
    if Result <> '' then
    begin
      Result := Result + ' ';
    end;
    Result := Result + WordCase(mText, Result = '');
  end;
end;

class function TEnumTables.TableName(const ATypeName: string): string;
begin
  Result := 'C' + Bare(ATypeName) + 'Names';
end;

class function TEnumTables.ResourceName(const ATypeName, AName, APrefix: string): string;
var
  Rest: string;
begin
  Rest := AName;
  if (APrefix <> '') and StartsStr(APrefix, Rest) then
  begin
    Delete(Rest, 1, Length(APrefix));
  end;
  Result := 'S' + Bare(ATypeName) + UpperCase(Copy(Rest, 1, 1)) + Copy(Rest, 2, MaxInt);
end;

function Contains(ANode: TSyntaxNode; const APosition: TTextPosition): Boolean;
begin
  Result := ((APosition.Line > ANode.StartPos.Line) or ((APosition.Line = ANode.StartPos.Line) and
    (APosition.Character >= ANode.StartPos.Character))) and ((APosition.Line < ANode.EndPos.Line) or
    ((APosition.Line = ANode.EndPos.Line) and (APosition.Character <= ANode.EndPos.Character)));
end;

/// <summary>Namen der Elemente; False bei festen Werten (a = 1) oder ohne Elemente.</summary>
function PlainNames(AEnum: TSyntaxNode; out ANames: TArray<string>): Boolean;
var
  Index: Integer;
begin
  ANames := nil;
  for Index := 0 to AEnum.ChildCount - 1 do
  begin
    if (AEnum[Index].Kind <> TSyntaxKind.Identifier) or (AEnum[Index].ChildCount > 0) then
    begin
      Exit(False);
    end;
    ANames := ANames + [AEnum[Index].Name];
  end;
  Result := ANames <> nil;
end;

class function TEnumTables.Target(ATree: TSyntaxTree; const APosition: TTextPosition; out ATarget: TEnumTarget;
  out AReason: string): Boolean;
var
  Decl, Enum: TSyntaxNode;
begin
  ATarget := Default(TEnumTarget);
  AReason := '';
  Decl := ATree.Root.Search(
    function(ANode: TSyntaxNode): TSyntaxSearchStep
    begin
      if not Contains(ANode, APosition) then
      begin
        Exit(TSyntaxSearchStep.Skip);
      end;
      if (ANode.Kind = TSyntaxKind.TypeDecl) and (ANode.FindChild(TSyntaxKind.EnumType) <> nil) then
      begin
        Exit(TSyntaxSearchStep.Found);
      end;
      Result := TSyntaxSearchStep.Descend;
    end);
  if Decl = nil then
  begin
    Exit(Fail(cTexts[TEditingEnumTablesText.NoEnumerationTypeAtThis].Text, AReason));
  end;
  Enum := Decl.FindChild(TSyntaxKind.EnumType);
  // Nur Typen der Unit: In Klassen und Routinen fehlt der Platz für eine Konstante dahinter.
  if (Decl.Parent = nil) or (Decl.Parent.Kind <> TSyntaxKind.TypeSection) or (Decl.Parent.Parent = nil) or
    not (Decl.Parent.Parent.Kind in [TSyntaxKind.InterfaceSection, TSyntaxKind.ImplementationSection,
    TSyntaxKind.ProgramFile, TSyntaxKind.LibraryFile]) then
  begin
    Exit(Fail(cTexts[TEditingEnumTablesText.IsNotDirectlyInThe].Fmt([Decl.Name]), AReason));
  end;
  if not PlainNames(Enum, ATarget.Names) then
  begin
    Exit(Fail(cTexts[TEditingEnumTablesText.HasElementsWithFixedValues].Fmt([Decl.Name]),
      AReason));
  end;
  ATarget.TypeName := Decl.Name;
  ATarget.NamePosition := Decl.StartPos;
  ATarget.InInterface := Decl.Parent.Parent.Kind = TSyntaxKind.InterfaceSection;
  Result := True;
end;

/// <summary>Auf oberster Ebene der Datei deklarierte Namen.</summary>
function DeclaredNames(ATree: TSyntaxTree): TArray<string>;
var
  Names: TArray<string>;
begin
  Names := nil;
  ATree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      if ANode.Kind in [TSyntaxKind.TypeDecl, TSyntaxKind.ConstDecl, TSyntaxKind.VarDecl] then
      begin
        Names := Names + [ANode.Name];
      end;
      Result := not (ANode.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.TypeDecl]);
    end);
  Result := Names;
end;

function IsIdentifier(const AName: string): Boolean;
var
  Index: Integer;
begin
  Result := (AName <> '') and (AName[1].IsLetter or (AName[1] = '_')) and not TPascalLexer.IsReservedWord(AName);
  for Index := 2 to Length(AName) do
  begin
    if not (AName[Index].IsLetterOrDigit or (AName[Index] = '_')) then
    begin
      Exit(False);
    end;
  end;
end;

function Joined(const AHead: string; const AItems: TArray<string>; const AIndent, ALineBreak: string): string;
var
  Line: string;
  Index: Integer;
begin
  Line := AHead + '(' + string.Join(', ', AItems) + ');';
  if Length(AIndent + Line) <= LineLimit then
  begin
    Exit(AIndent + Line);
  end;
  Result := AIndent + AHead + '(';
  for Index := 0 to High(AItems) do
  begin
    Result := Result + ALineBreak + AIndent + '  ' + AItems[Index];
    if Index < High(AItems) then
    begin
      Result := Result + ',';
    end;
  end;
  Result := Result + ');';
end;

/// <summary>Deklaration des Aufzählungstyps, in der APosition liegt; nil ohne.</summary>
function EnumDeclAt(ATree: TSyntaxTree; const APosition: TTextPosition): TSyntaxNode;
var
  mPosition: TTextPosition;
begin
  mPosition := APosition;
  Result := ATree.Root.Search(
    function(ANode: TSyntaxNode): TSyntaxSearchStep
    begin
      if not Contains(ANode, mPosition) then
      begin
        Exit(TSyntaxSearchStep.Skip);
      end;
      if (ANode.Kind = TSyntaxKind.TypeDecl) and (ANode.FindChild(TSyntaxKind.EnumType) <> nil) then
      begin
        Exit(TSyntaxSearchStep.Found);
      end;
      Result := TSyntaxSearchStep.Descend;
    end);
end;

/// <summary>Grund, warum AName nicht als Name der Tabelle taugt; '' wenn er passt.</summary>
function NameError(const AName: string; const ATaken: TArray<string>): string;
begin
  Result := '';
  if not IsIdentifier(AName) then
  begin
    Result := cTexts[TEditingEnumTablesText.IsNotAValidName].Fmt([AName]);
  end
  else if IndexText(AName, ATaken) >= 0 then
  begin
    Result := cTexts[TEditingEnumTablesText.TheNameIsAlreadyTaken].Fmt([AName]);
  end;
end;

type
  /// <summary>Text der neuen Tabelle samt resourcestrings.</summary>
  TTableDraft = record
    Info: TEnumTarget;
    Request: TEnumTableRequest;
    Prefix: string;
    Indent: string;
    LineBreak: string;
    Items: TArray<string>;
    Resources: TArray<string>;
    /// <summary>Einträge und resourcestring-Namen; False mit Grund, wenn ein Name schon vergeben ist.</summary>
    function CollectItems(const ATaken: TArray<string>; out AReason: string): Boolean;
    /// <summary>resourcestring-Abschnitt (falls gewünscht) und const-Abschnitt mit der Tabelle.</summary>
    function Declaration: string;
  end;

function TTableDraft.CollectItems(const ATaken: TArray<string>; out AReason: string): Boolean;
var
  mName, mResource: string;
begin
  AReason := '';
  Items := nil;
  Resources := nil;
  for mName in Info.Names do
  begin
    if not Request.ResourceStrings then
    begin
      Items := Items + [QuotedStr(TEnumTables.DisplayText(mName, Prefix))];
      Continue;
    end;
    mResource := TEnumTables.ResourceName(Info.TypeName, mName, Prefix);
    if IndexText(mResource, ATaken + Resources) >= 0 then
    begin
      Exit(Fail(cTexts[TEditingEnumTablesText.TheNameIsAlreadyTaken].Fmt([mResource]), AReason));
    end;
    Resources := Resources + [mResource];
    Items := Items + ['@' + mResource];
  end;
  Result := True;
end;

function TTableDraft.Declaration: string;
var
  mIndex: Integer;
begin
  if not Request.ResourceStrings then
  begin
    Exit(Indent + 'const' + LineBreak + Joined(Request.Name + ': array[' + Info.TypeName + '] of string = ', Items,
      Indent + '  ', LineBreak));
  end;
  Result := Indent + 'resourcestring';
  for mIndex := 0 to High(Resources) do
  begin
    Result := Result + LineBreak + Indent + '  ' + Resources[mIndex] + ' = ' +
      QuotedStr(TEnumTables.DisplayText(Info.Names[mIndex], Prefix)) + ';';
  end;
  Result := Result + LineBreak + LineBreak + Indent + 'const' + LineBreak +
    Joined(Request.Name + ': array[' + Info.TypeName + '] of PResStringRec = ', Items, Indent + '  ', LineBreak);
end;

/// <summary>Einfügen direkt hinter der Deklaration ADecl; folgen im Abschnitt weitere Typen, beginnt für sie ein
/// neuer Typabschnitt.</summary>
function AfterTypeEdit(const ALines: TLineTable; ADecl: TSyntaxNode; const ADraft: TTableDraft): TTextEdit;
var
  mPosition: TTextPosition;
  mText: string;
begin
  mPosition := ALines.PositionAt(ALines.LineContentEnd(ALines.PositionAt(ADecl.EndOffset).Line));
  mText := ADraft.LineBreak + ADraft.LineBreak + ADraft.Declaration;
  if ADecl.Parent[ADecl.Parent.ChildCount - 1] <> ADecl then
  begin
    mText := mText + ADraft.LineBreak + ADraft.LineBreak + ADraft.Indent + 'type';
  end;
  Result := TTextEdit.Create(TTextRange.Create(mPosition, mPosition), mText);
end;

/// <summary>Stelle im implementation-Teil hinter dessen uses bzw. hinter "implementation"; False ohne
/// implementation-Teil.</summary>
function ImplementationOffset(ATree: TSyntaxTree; const ALines: TLineTable; out AOffset: Integer): Boolean;
var
  mSection, mUses: TSyntaxNode;
begin
  AOffset := 0;
  mSection := ATree.Root.FindChild(TSyntaxKind.ImplementationSection);
  Result := mSection <> nil;
  if not Result then
  begin
    Exit;
  end;
  mUses := mSection.FindChild(TSyntaxKind.UsesClause);
  if mUses <> nil then
  begin
    AOffset := ALines.LineContentEnd(ALines.PositionAt(mUses.EndOffset).Line);
  end
  else
  begin
    AOffset := ALines.LineContentEnd(ALines.PositionAt(mSection.StartOffset).Line);
  end;
end;

class function TEnumTables.CreateTable(const AText: string; ATree: TSyntaxTree; const APosition: TTextPosition;
  const ARequest: TEnumTableRequest; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  mDraft: TTableDraft;
  mTaken: TArray<string>;
  mLines: TLineTable;
  mDecl: TSyntaxNode;
  mOffset: Integer;
  mPosition: TTextPosition;
begin
  AEdits := nil;
  mDraft := Default(TTableDraft);
  mDraft.Request := ARequest;
  Result := Target(ATree, APosition, mDraft.Info, AReason);
  if Result then
  begin
    mTaken := DeclaredNames(ATree);
    AReason := NameError(ARequest.Name, mTaken);
    Result := AReason = '';
  end;
  if not Result then
  begin
    Exit;
  end;
  mLines := TLineTable.Build(AText);
  mDecl := EnumDeclAt(ATree, APosition);
  mDraft.LineBreak := TTextLines.LineBreakOf(AText);
  mDraft.Indent := TTextLines.IndentOf(AText, mLines.PositionAt(mDecl.Parent.StartOffset).Line);
  mDraft.Prefix := CommonPrefix(mDraft.Info.Names);
  if not mDraft.CollectItems(mTaken, AReason) then
  begin
    Exit(False);
  end;
  if (ARequest.Placement = TEnumTablePlacement.AfterType) or not mDraft.Info.InInterface then
  begin
    AEdits := [AfterTypeEdit(mLines, mDecl, mDraft)];
  end
  else if ImplementationOffset(ATree, mLines, mOffset) then
  begin
    mPosition := mLines.PositionAt(mOffset);
    AEdits := [TTextEdit.Create(TTextRange.Create(mPosition, mPosition),
      mDraft.LineBreak + mDraft.LineBreak + mDraft.Declaration)];
  end
  else
  begin
    Exit(Fail(cTexts[TEditingEnumTablesText.TheUnitHasNoImplementation].Text, AReason));
  end;
end;

function TableOf(ANode: TSyntaxNode; out ATable: TEnumTable): Boolean;
var
  ArrayNode, Value: TSyntaxNode;
begin
  Result := False;
  ATable := Default(TEnumTable);
  if not (ANode.Kind in [TSyntaxKind.ConstDecl, TSyntaxKind.VarDecl]) then
  begin
    Exit;
  end;
  ArrayNode := ANode.FindChild(TSyntaxKind.ArrayType);
  Value := ANode.FindChild(TSyntaxKind.ParenExpr);
  // Eine Dimension über einen benannten Typ: array[TTyp] of X.
  if (ArrayNode = nil) or (Value = nil) or (ArrayNode.ChildCount <> 2) or
    (ArrayNode[0].Kind <> TSyntaxKind.TypeReference) or (ArrayNode[0].ChildCount > 0) then
  begin
    Exit;
  end;
  ATable.Decl := ANode;
  ATable.IndexType := ArrayNode[0];
  ATable.ElementType := ArrayNode[1];
  ATable.Value := Value;
  Result := True;
end;

class function TEnumTables.Tables(ATree: TSyntaxTree): TArray<TEnumTable>;
var
  Found: TArray<TEnumTable>;
begin
  Found := nil;
  ATree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    var
      Table: TEnumTable;
    begin
      if TableOf(ANode, Table) then
      begin
        Found := Found + [Table];
      end;
      Result := not (ANode.Kind in [TSyntaxKind.ConstDecl, TSyntaxKind.VarDecl]);
    end);
  Result := Found;
end;

class function TEnumTables.TableAt(ATree: TSyntaxTree; const APosition: TTextPosition;
  out ATable: TEnumTable): Boolean;
var
  Table: TEnumTable;
begin
  ATable := Default(TEnumTable);
  for Table in Tables(ATree) do
  begin
    if Contains(Table.Decl, APosition) then
    begin
      ATable := Table;
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TEnumTables.ElementOf(const ATypeName: string): TEnumTableElement;
var
  Name: string;
begin
  Name := LowerCase(ATypeName);
  if MatchText(Name, ['string', 'unicodestring', 'ansistring', 'widestring', 'shortstring', 'rawbytestring',
    'utf8string']) then
  begin
    Result := TEnumTableElement.Text;
  end
  else if MatchText(Name, ['integer', 'cardinal', 'int64', 'uint64', 'byte', 'word', 'longint', 'longword',
    'shortint', 'smallint', 'nativeint', 'nativeuint', 'int8', 'int16', 'int32', 'uint8', 'uint16', 'uint32']) then
  begin
    Result := TEnumTableElement.Number;
  end
  else if MatchText(Name, ['double', 'single', 'extended', 'real', 'currency']) then
  begin
    Result := TEnumTableElement.Float;
  end
  else if MatchText(Name, ['boolean', 'bytebool', 'wordbool', 'longbool']) then
  begin
    Result := TEnumTableElement.Boolean_;
  end
  else if MatchText(Name, ['char', 'widechar', 'ansichar']) then
  begin
    Result := TEnumTableElement.Char_;
  end
  else if MatchText(Name, ['pointer', 'tclass', 'pchar', 'pansichar', 'pwidechar']) then
  begin
    Result := TEnumTableElement.Pointer_;
  end
  else if SameText(Name, 'presstringrec') then
  begin
    Result := TEnumTableElement.ResourceString_;
  end
  else
  begin
    Result := TEnumTableElement.Other;
  end;
end;

type
  /// <summary>Ein Kommentar zwischen zwei Einträgen.</summary>
  TGapComment = record
    Text: string;
    /// <summary>Gehört zum Eintrag davor (False: zum Eintrag danach).</summary>
    ToPrevious: Boolean;
    IsLine: Boolean;
  end;

  /// <summary>Text zwischen zwei Einträgen [Start, Stop); HasPrevious/HasNext: gibt es die Einträge davor und
  /// danach.</summary>
  TGap = record
    Start: Integer;
    Stop: Integer;
    HasPrevious: Boolean;
    HasNext: Boolean;
    class function Create(AStart, AStop: Integer; AHasPrevious, AHasNext: Boolean): TGap; static;
    /// <summary>Gehört der Kommentar, der bei ACommentStop endet, zum vorigen Eintrag? Vor dem Komma ja,
    /// dahinter nur, wenn ein Zeilenumbruch vor dem nächsten Eintrag folgt (Zeilenkommentar hinter "'New',").
    /// </summary>
    function ToPrevious(const AText: string; ACommentStop: Integer; AAfterComma: Boolean): Boolean;
  end;

class function TGap.Create(AStart, AStop: Integer; AHasPrevious, AHasNext: Boolean): TGap;
begin
  Result.Start := AStart;
  Result.Stop := AStop;
  Result.HasPrevious := AHasPrevious;
  Result.HasNext := AHasNext;
end;

function TGap.ToPrevious(const AText: string; ACommentStop: Integer; AAfterComma: Boolean): Boolean;
var
  mTail: string;
begin
  if not HasNext then
  begin
    Result := True;
  end
  else if not HasPrevious then
  begin
    Result := False;
  end
  else if not AAfterComma then
  begin
    Result := True;
  end
  else
  begin
    mTail := Copy(AText, ACommentStop + 1, Stop - ACommentStop);
    Result := (Pos(#10, mTail) > 0) or (Pos(#13, mTail) > 0);
  end;
end;

/// <summary>Ende des geschlossenen Kommentars: Position des Schlusszeichens plus AExtra; AStop ohne.</summary>
function ClosedEnd(APosition, AExtra, AStop: Integer): Integer;
begin
  Result := AStop;
  if APosition > 0 then
  begin
    Result := APosition + AExtra;
  end;
end;

/// <summary>Ende des Kommentars, der an AIndex (0-basiert) beginnt, höchstens AStop; -1 ohne Kommentar.</summary>
function CommentEnd(const AText: string; AIndex, AStop: Integer; out AIsLine: Boolean): Integer;
begin
  AIsLine := False;
  Result := -1;
  if AText[AIndex + 1] = '{' then
  begin
    Result := ClosedEnd(PosEx('}', AText, AIndex + 2), 0, AStop);
  end
  else if (AText[AIndex + 1] = '(') and (AIndex + 1 < AStop) and (AText[AIndex + 2] = '*') then
  begin
    Result := ClosedEnd(PosEx('*)', AText, AIndex + 3), 1, AStop);
  end
  else if (AText[AIndex + 1] = '/') and (AIndex + 1 < AStop) and (AText[AIndex + 2] = '/') then
  begin
    Result := AIndex + 1;
    while (Result < AStop) and not CharInSet(AText[Result + 1], [#13, #10]) do
    begin
      Inc(Result);
    end;
    AIsLine := True;
  end;
  if Result > AStop then
  begin
    Result := AStop;
  end;
end;

/// <summary>Kommentare in der Lücke AGap; AComma: Stelle des Kommatas darin, -1 ohne.</summary>
function GapComments(const AText: string; const AGap: TGap; out AComma: Integer): TArray<TGapComment>;
var
  mIndex, mStop: Integer;
  mComment: TGapComment;
begin
  Result := nil;
  AComma := -1;
  mIndex := AGap.Start;
  while mIndex < AGap.Stop do
  begin
    mComment := Default(TGapComment);
    mStop := CommentEnd(AText, mIndex, AGap.Stop, mComment.IsLine);
    if AText[mIndex + 1] = ',' then
    begin
      AComma := mIndex;
      Inc(mIndex);
    end
    else if mStop < 0 then
    begin
      Inc(mIndex);
    end
    else
    begin
      mComment.Text := Copy(AText, mIndex + 1, mStop - mIndex);
      mComment.ToPrevious := AGap.ToPrevious(AText, mStop, AComma >= 0);
      Result := Result + [mComment];
      mIndex := mStop;
    end;
  end;
end;

/// <summary>Buchstabe, Ziffer oder Unterstrich an AIndex (False außerhalb von AText).</summary>
function IsNamePartAt(const AText: string; AIndex: Integer): Boolean;
begin
  Result := (AIndex >= 1) and (AIndex <= Length(AText)) and (AText[AIndex].IsLetterOrDigit or (AText[AIndex] = '_'));
end;

function HasWord(const AText, AWord: string): Boolean;
var
  mIndex: Integer;
begin
  mIndex := Pos(LowerCase(AWord), LowerCase(AText));
  while mIndex > 0 do
  begin
    if not IsNamePartAt(AText, mIndex - 1) and not IsNamePartAt(AText, mIndex + Length(AWord)) then
    begin
      Exit(True);
    end;
    mIndex := PosEx(LowerCase(AWord), LowerCase(AText), mIndex + 1);
  end;
  Result := False;
end;

function LiteralText(ANode: TSyntaxNode; out AValue: string): Boolean;
begin
  Result := (ANode.Kind = TSyntaxKind.Literal) and (Length(ANode.Name) >= 2) and (ANode.Name[1] = '''') and
    (ANode.Name[Length(ANode.Name)] = '''');
  if Result then
  begin
    AValue := StringReplace(Copy(ANode.Name, 2, Length(ANode.Name) - 2), '''''', '''', [rfReplaceAll]);
  end;
end;

/// <summary>Element, dessen Name in einem der Kommentare steht; -1 ohne.</summary>
function CommentMatch(const AComments, ANames: TArray<string>): Integer;
var
  mComment: string;
  mIndex: Integer;
begin
  for mComment in AComments do
  begin
    for mIndex := 0 to High(ANames) do
    begin
      if HasWord(mComment, ANames[mIndex]) then
      begin
        Exit(mIndex);
      end;
    end;
  end;
  Result := -1;
end;

/// <summary>Element mit dem Namen oder Text AValue; -1 ohne.</summary>
function NameOrTextIndex(const AValue: string; const ANames, ATexts: TArray<string>): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(ANames) do
  begin
    if SameText(AValue, ATexts[mIndex]) or SameText(AValue, ANames[mIndex]) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

/// <summary>Element zu einem Text im Eintrag selbst oder in einem Record (A: 'Neu'; B: 1); -1 ohne.</summary>
function LiteralMatch(AEntry: TSyntaxNode; const ANames, ATexts: TArray<string>): Integer;
var
  mCandidates: TArray<TSyntaxNode>;
  mCandidate: TSyntaxNode;
  mIndex: Integer;
  mValue: string;
begin
  mCandidates := [AEntry];
  if AEntry.Kind = TSyntaxKind.ParenExpr then
  begin
    for mIndex := 0 to AEntry.ChildCount - 1 do
    begin
      mCandidates := mCandidates + [AEntry[mIndex]];
    end;
  end;
  Result := -1;
  for mCandidate in mCandidates do
  begin
    if (Result < 0) and LiteralText(mCandidate, mValue) then
    begin
      Result := NameOrTextIndex(Trim(mValue), ANames, ATexts);
    end;
  end;
end;

/// <summary>Bezeichner im Eintrag: @SOrderStatePaid, osPaid; '' ohne.</summary>
function IdentifierOf(AEntry: TSyntaxNode): string;
begin
  Result := '';
  if (AEntry.Kind = TSyntaxKind.AddressOf) and (AEntry.ChildCount = 1) and
    (AEntry[0].Kind = TSyntaxKind.Identifier) then
  begin
    Result := AEntry[0].Name;
  end
  else if AEntry.Kind = TSyntaxKind.Identifier then
  begin
    Result := AEntry.Name;
  end;
end;

/// <summary>Element namens AIdentifier, sonst das mit dem längsten Namensrest (ohne APrefix) am Ende von
/// AIdentifier; -1 ohne.</summary>
function IdentifierMatch(const AIdentifier: string; const ANames: TArray<string>; const APrefix: string): Integer;
var
  mIndex, mBestLength: Integer;
  mRest: string;
begin
  Result := -1;
  if AIdentifier = '' then
  begin
    Exit;
  end;
  mBestLength := 0;
  for mIndex := 0 to High(ANames) do
  begin
    if SameText(AIdentifier, ANames[mIndex]) then
    begin
      Exit(mIndex);
    end;
    mRest := Copy(ANames[mIndex], Length(APrefix) + 1, MaxInt);
    if (mRest <> '') and EndsText(mRest, AIdentifier) and (Length(mRest) > mBestLength) then
    begin
      Result := mIndex;
      mBestLength := Length(mRest);
    end;
  end;
end;

/// <summary>Element, zu dem der Eintrag AEntry passt; -1 ohne. AStrong: über einen Kommentar.</summary>
function MatchOf(AEntry: TSyntaxNode; const AComments: TArray<string>; const ANames, ATexts: TArray<string>;
  const APrefix: string; out AStrong: Boolean): Integer;
begin
  Result := CommentMatch(AComments, ANames);
  AStrong := Result >= 0;
  if Result < 0 then
  begin
    Result := LiteralMatch(AEntry, ANames, ATexts);
  end;
  if Result < 0 then
  begin
    Result := IdentifierMatch(IdentifierOf(AEntry), ANames, APrefix);
  end;
end;

/// <summary>Zuordnung Eintrag → Element, nur aufsteigend (längste aufsteigende Folge), sonst -1.</summary>
function Increasing(const AMatches: TArray<Integer>): TArray<Integer>;
var
  Length_, Index, Earlier, Best: Integer;
  Lengths, Previous: TArray<Integer>;
begin
  Length_ := Length(AMatches);
  SetLength(Result, Length_);
  SetLength(Lengths, Length_);
  SetLength(Previous, Length_);
  Best := -1;
  for Index := 0 to Length_ - 1 do
  begin
    Result[Index] := -1;
    Lengths[Index] := 0;
    Previous[Index] := -1;
    if AMatches[Index] < 0 then
    begin
      Continue;
    end;
    Lengths[Index] := 1;
    for Earlier := 0 to Index - 1 do
    begin
      if (AMatches[Earlier] >= 0) and (AMatches[Earlier] < AMatches[Index]) and
        (Lengths[Earlier] + 1 > Lengths[Index]) then
      begin
        Lengths[Index] := Lengths[Earlier] + 1;
        Previous[Index] := Earlier;
      end;
    end;
    if (Best < 0) or (Lengths[Index] > Lengths[Best]) then
    begin
      Best := Index;
    end;
  end;
  while Best >= 0 do
  begin
    Result[Best] := AMatches[Best];
    Best := Previous[Best];
  end;
end;

/// <summary>Beginnt der Eintrag an AOffset seine Zeile?</summary>
function StartsLine(const AText: string; AOffset: Integer): Boolean;
var
  Index: Integer;
begin
  Index := AOffset;
  while (Index > 0) and CharInSet(AText[Index], [' ', #9]) do
  begin
    Dec(Index);
  end;
  Result := (Index = 0) or CharInSet(AText[Index], [#13, #10]);
end;

/// <summary>resourcestring-Deklaration namens AName in ATree; nil ohne.</summary>
function ResourceDecl(ATree: TSyntaxTree; const AName: string): TSyntaxNode;
begin
  Result := nil;
  if ATree = nil then
  begin
    Exit;
  end;
  Result := ATree.Root.Search(
    function(ANode: TSyntaxNode): TSyntaxSearchStep
    begin
      if (ANode.Kind = TSyntaxKind.ConstDecl) and SameText(ANode.Name, AName) and (ANode.Parent <> nil) and
        SameText(ANode.Parent.Name, 'resourcestring') then
      begin
        Exit(TSyntaxSearchStep.Found);
      end;
      if ANode.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.TypeDecl, TSyntaxKind.ConstDecl] then
      begin
        Exit(TSyntaxSearchStep.Skip);
      end;
      Result := TSyntaxSearchStep.Descend;
    end);
end;

/// <summary>Texte der Elemente, wie DisplayText sie bildet.</summary>
function DisplayTexts(const ANames: TArray<string>; const APrefix: string): TArray<string>;
var
  mName: string;
begin
  Result := nil;
  for mName in ANames do
  begin
    Result := Result + [TEnumTables.DisplayText(mName, APrefix)];
  end;
end;

/// <summary>Ist einer der Kommentare ein Zeilenkommentar?</summary>
function HasLineComment(const AComments: TArray<string>): Boolean;
var
  mComment: string;
begin
  Result := False;
  for mComment in AComments do
  begin
    Result := Result or StartsStr('//', mComment);
  end;
end;

/// <summary>Ist das Element von AMatches[AEntry] schon einem früheren Eintrag zugeordnet?</summary>
function UsedBefore(const AMatches: TArray<Integer>; AEntry: Integer): Boolean;
var
  mIndex: Integer;
begin
  Result := False;
  for mIndex := 0 to AEntry - 1 do
  begin
    Result := Result or ((AMatches[AEntry] >= 0) and (AMatches[mIndex] = AMatches[AEntry]));
  end;
end;

/// <summary>Nächster zugeordneter Eintrag hinter AEntry; Length(AAligned) ohne.</summary>
function NextAligned(const AAligned: TArray<Integer>; AEntry: Integer): Integer;
begin
  Result := AEntry + 1;
  while (Result <= High(AAligned)) and (AAligned[Result] < 0) do
  begin
    Inc(Result);
  end;
end;

/// <summary>Steht jeder Eintrag außer dem ersten am Anfang seiner Zeile (mindestens zwei Einträge)?</summary>
function IsMultiLine(const AText: string; AValue: TSyntaxNode): Boolean;
var
  mEntry: Integer;
begin
  Result := AValue.ChildCount >= 2;
  for mEntry := 1 to AValue.ChildCount - 1 do
  begin
    Result := Result and StartsLine(AText, AValue[mEntry].StartOffset);
  end;
end;

type
  /// <summary>Ein neuer resourcestring hinter dem des Nachbarn; mehrere an derselben Stelle gesammelt, damit sie
  /// in Reihenfolge stehen.</summary>
  TPendingResource = record
    Offset: Integer;
    Text: string;
  end;

  /// <summary>Bringt den Klammerwert einer Tabelle auf die Elemente (TEnumTables.Repair).</summary>
  TTableRepairer = class
  strict private
    FText: string;
    FTree: TSyntaxTree;
    FValue: TSyntaxNode;
    FNames: TArray<string>;
    FValues: TEnumTableValues;
    FLines: TLineTable;
    FCount: Integer;
    FPrefix: string;
    FLineBreak: string;
    FIndent: string;
    FLineComments: Boolean;
    FMultiLine: Boolean;
    FTaken: TArray<string>;
    FResources: TArray<TPendingResource>;
    FRepair: TEnumTableRepair;
    function Entries(AIndex: Integer): TSyntaxNode;
    function At(AOffset: Integer): TTextPosition;
    procedure AddEdit(AStart, AStop: Integer; const ANewText: string);
    procedure AddResource(AOffset: Integer; const ANewText: string);
    function ResourceValue(const AName: string; ANeighbor: Integer): string;
    function ValueFor(const AName: string; ANeighbor: Integer): string;
    function WithComment(const AEntry, AName: string): string;
    procedure InsertInline(AAfter: Integer; const ANew: TArray<string>);
    procedure InsertBefore(AEntry: Integer; const ANew, ANewNames: TArray<string>);
    procedure InsertFirst(const ANew, ANewNames: TArray<string>);
    procedure InsertLast(AAfter: Integer; const ANew, ANewNames: TArray<string>);
    /// <summary>Fügt die Werte ANew nach dem Eintrag AAfter (-1: vor dem ersten) ein.</summary>
    procedure Insert(AAfter: Integer; const ANew, ANewNames: TArray<string>);
    procedure RemoveAtEnd(AFirst, ALast: Integer);
    /// <summary>Entfernt die Einträge AFirst..ALast.</summary>
    procedure Remove(AFirst, ALast: Integer);
    function GapAt(AGap: Integer): TGap;
    function EntryComments: TArray<TArray<string>>;
    function Matches(const AComments: TArray<TArray<string>>): TArray<Integer>;
    procedure AddMissing(AFirstName, ALastName, AAfter, ANextEntry: Integer);
    procedure RepairGap(APreviousName, APreviousEntry, ANextName, ANextEntry: Integer);
    procedure RepairGaps(const AAligned: TArray<Integer>);
  public
    constructor Create(const AText: string; ATree: TSyntaxTree; AValue: TSyntaxNode; const ANames: TArray<string>;
      const AValues: TEnumTableValues);
    function Run(out ARepair: TEnumTableRepair): Boolean;
  end;

constructor TTableRepairer.Create(const AText: string; ATree: TSyntaxTree; AValue: TSyntaxNode;
  const ANames: TArray<string>; const AValues: TEnumTableValues);
begin
  inherited Create;
  FText := AText;
  FTree := ATree;
  FValue := AValue;
  FNames := ANames;
  FValues := AValues;
  FCount := AValue.ChildCount;
end;

function TTableRepairer.Entries(AIndex: Integer): TSyntaxNode;
begin
  Result := FValue[AIndex];
end;

function TTableRepairer.At(AOffset: Integer): TTextPosition;
begin
  Result := FLines.PositionAt(AOffset);
end;

procedure TTableRepairer.AddEdit(AStart, AStop: Integer; const ANewText: string);
begin
  FRepair.Edits := FRepair.Edits + [TTextEdit.Create(TTextRange.Create(At(AStart), At(AStop)), ANewText)];
end;

procedure TTableRepairer.AddResource(AOffset: Integer; const ANewText: string);
var
  mItem: Integer;
  mResource: TPendingResource;
begin
  for mItem := 0 to High(FResources) do
  begin
    if FResources[mItem].Offset = AOffset then
    begin
      FResources[mItem].Text := FResources[mItem].Text + ANewText;
      Exit;
    end;
  end;
  mResource.Offset := AOffset;
  mResource.Text := ANewText;
  FResources := FResources + [mResource];
end;

function TTableRepairer.ResourceValue(const AName: string; ANeighbor: Integer): string;
var
  mNode: TSyntaxNode;
  mName: string;
begin
  // Neuer resourcestring hinter dem des Nachbarn; ohne ihn ein nil-Platzhalter.
  mNode := nil;
  if (ANeighbor >= 0) and (Entries(ANeighbor).Kind = TSyntaxKind.AddressOf) and (Entries(ANeighbor).ChildCount = 1) then
  begin
    mNode := ResourceDecl(FTree, Entries(ANeighbor)[0].Name);
  end;
  if mNode = nil then
  begin
    Exit('nil {TODO ' + AName + '}');
  end;
  if FTaken = nil then
  begin
    FTaken := DeclaredNames(FTree);
  end;
  mName := TResourceStrings.UniqueName(TEnumTables.ResourceName(FValues.IndexType, AName, FPrefix), FTaken);
  FTaken := FTaken + [mName];
  AddResource(FLines.LineContentEnd(At(mNode.EndOffset).Line), FLineBreak +
    TTextLines.IndentOf(FText, At(mNode.StartOffset).Line) + mName + ' = ' +
    QuotedStr(TEnumTables.DisplayText(AName, FPrefix)) + ';');
  Result := '@' + mName;
end;

function TTableRepairer.ValueFor(const AName: string; ANeighbor: Integer): string;
var
  mTodo: string;
begin
  mTodo := ' {TODO ' + AName + '}';
  case FValues.Element of
    TEnumTableElement.Text:
      Result := QuotedStr(TEnumTables.DisplayText(AName, FPrefix));
    TEnumTableElement.Number:
      Result := '0' + mTodo;
    TEnumTableElement.Float:
      Result := '0.0' + mTodo;
    TEnumTableElement.Boolean_:
      Result := 'False' + mTodo;
    TEnumTableElement.Char_:
      Result := '#0' + mTodo;
    TEnumTableElement.Pointer_:
      Result := 'nil' + mTodo;
    TEnumTableElement.Enum:
      Result := 'Low(' + FValues.ElementType + ')' + mTodo;
    TEnumTableElement.ResourceString_:
      Result := ResourceValue(AName, ANeighbor);
  else
    // Kopie des Nachbarn als Muster (Records, eigene Typen).
    Result := 'Default' + mTodo;
    if ANeighbor >= 0 then
    begin
      Result := Copy(FText, Entries(ANeighbor).StartOffset + 1, Entries(ANeighbor).EndOffset -
        Entries(ANeighbor).StartOffset) + mTodo;
    end;
  end;
end;

function TTableRepairer.WithComment(const AEntry, AName: string): string;
begin
  Result := AEntry;
  if FLineComments and FMultiLine then
  begin
    Result := Result + ' // ' + AName;
  end;
end;

procedure TTableRepairer.InsertInline(AAfter: Integer; const ANew: TArray<string>);
begin
  if AAfter >= 0 then
  begin
    AddEdit(Entries(AAfter).EndOffset, Entries(AAfter).EndOffset, ', ' + string.Join(', ', ANew));
  end
  else
  begin
    AddEdit(Entries(0).StartOffset, Entries(0).StartOffset, string.Join(', ', ANew) + ', ');
  end;
end;

procedure TTableRepairer.InsertBefore(AEntry: Integer; const ANew, ANewNames: TArray<string>);
var
  mItem, mStart: Integer;
  mText: string;
begin
  // Vor die Zeile des Eintrags AEntry.
  mText := '';
  for mItem := 0 to High(ANew) do
  begin
    mText := mText + FIndent + WithComment(ANew[mItem] + ',', ANewNames[mItem]) + FLineBreak;
  end;
  mStart := FLines.LineStart(At(Entries(AEntry).StartOffset).Line);
  AddEdit(mStart, mStart, mText);
end;

procedure TTableRepairer.InsertFirst(const ANew, ANewNames: TArray<string>);
var
  mItem, mStart: Integer;
  mText: string;
begin
  mText := '';
  for mItem := 0 to High(ANew) do
  begin
    mText := mText + WithComment(ANew[mItem] + ',', ANewNames[mItem]) + FLineBreak + FIndent;
  end;
  if StartsLine(FText, Entries(0).StartOffset) then
  begin
    mStart := FLines.LineStart(At(Entries(0).StartOffset).Line);
    AddEdit(mStart, mStart, FIndent + Copy(mText, 1, Length(mText) - Length(FIndent)));
  end
  else
  begin
    AddEdit(Entries(0).StartOffset, Entries(0).StartOffset, mText);
  end;
end;

procedure TTableRepairer.InsertLast(AAfter: Integer; const ANew, ANewNames: TArray<string>);
var
  mItem, mEnd, mLineEnd: Integer;
  mText, mClose: string;
begin
  // Hinter den letzten Eintrag: Komma an ihn, neue Zeilen dahinter.
  mEnd := Entries(AAfter).EndOffset;
  mLineEnd := FLines.LineContentEnd(At(mEnd).Line);
  mText := '';
  if FValue.EndOffset - 1 < mLineEnd then
  begin
    for mItem := 0 to High(ANew) do
    begin
      mText := mText + ',' + FLineBreak + FIndent + ANew[mItem];
    end;
    AddEdit(mEnd, mEnd, mText);
    Exit;
  end;
  for mItem := 0 to High(ANew) do
  begin
    mClose := '';
    if mItem < High(ANew) then
    begin
      mClose := ',';
    end;
    mText := mText + FLineBreak + FIndent + WithComment(ANew[mItem] + mClose, ANewNames[mItem]);
  end;
  // Ein Eintrag an derselben Stelle: Reihenfolge gleicher Stellen ist nicht festgelegt.
  if mLineEnd = mEnd then
  begin
    AddEdit(mLineEnd, mLineEnd, ',' + mText);
  end
  else
  begin
    AddEdit(mEnd, mEnd, ',');
    AddEdit(mLineEnd, mLineEnd, mText);
  end;
end;

procedure TTableRepairer.Insert(AAfter: Integer; const ANew, ANewNames: TArray<string>);
begin
  if not FMultiLine then
  begin
    InsertInline(AAfter, ANew);
  end
  else if (AAfter >= 0) and (AAfter < FCount - 1) then
  begin
    InsertBefore(AAfter + 1, ANew, ANewNames);
  end
  else if AAfter < 0 then
  begin
    InsertFirst(ANew, ANewNames);
  end
  else
  begin
    InsertLast(AAfter, ANew, ANewNames);
  end;
end;

procedure TTableRepairer.RemoveAtEnd(AFirst, ALast: Integer);
var
  mComma: Integer;
begin
  // Am Ende: das Komma hinter dem vorigen Eintrag fällt mit weg.
  GapComments(FText, TGap.Create(Entries(AFirst - 1).EndOffset, Entries(AFirst).StartOffset, True, True), mComma);
  if not FMultiLine or (mComma < 0) then
  begin
    AddEdit(Entries(AFirst - 1).EndOffset, Entries(ALast).EndOffset, '');
    Exit;
  end;
  AddEdit(mComma, mComma + 1, '');
  if (FValue.EndOffset - 1) < FLines.LineContentEnd(At(Entries(ALast).EndOffset).Line) then
  begin
    AddEdit(Entries(AFirst).StartOffset, FValue.EndOffset - 1, '');
  end
  else
  begin
    AddEdit(FLines.LineContentEnd(At(Entries(AFirst).StartOffset).Line - 1),
      FLines.LineContentEnd(At(Entries(ALast).EndOffset).Line), '');
  end;
end;

procedure TTableRepairer.Remove(AFirst, ALast: Integer);
var
  mItem: Integer;
begin
  for mItem := AFirst to ALast do
  begin
    FRepair.Removed := FRepair.Removed + [Copy(FText, Entries(mItem).StartOffset + 1, Entries(mItem).EndOffset -
      Entries(mItem).StartOffset)];
  end;
  if ALast >= FCount - 1 then
  begin
    RemoveAtEnd(AFirst, ALast);
  end
  else if FMultiLine and StartsLine(FText, Entries(AFirst).StartOffset) then
  begin
    AddEdit(FLines.LineStart(At(Entries(AFirst).StartOffset).Line),
      FLines.LineStart(At(Entries(ALast + 1).StartOffset).Line), '');
  end
  else
  begin
    AddEdit(Entries(AFirst).StartOffset, Entries(ALast + 1).StartOffset, '');
  end;
end;

function TTableRepairer.GapAt(AGap: Integer): TGap;
begin
  if AGap = 0 then
  begin
    Result := TGap.Create(FValue.StartOffset + 1, Entries(0).StartOffset, False, True);
  end
  else if AGap = FCount then
  begin
    Result := TGap.Create(Entries(FCount - 1).EndOffset, FValue.EndOffset - 1, True, False);
  end
  else
  begin
    Result := TGap.Create(Entries(AGap - 1).EndOffset, Entries(AGap).StartOffset, True, True);
  end;
end;

function TTableRepairer.EntryComments: TArray<TArray<string>>;
var
  mGap, mComma: Integer;
  mComment: TGapComment;
begin
  SetLength(Result, FCount);
  for mGap := 0 to FCount do
  begin
    for mComment in GapComments(FText, GapAt(mGap), mComma) do
    begin
      if mComment.ToPrevious then
      begin
        Result[mGap - 1] := Result[mGap - 1] + [mComment.Text];
      end
      else
      begin
        Result[mGap] := Result[mGap] + [mComment.Text];
      end;
    end;
  end;
end;

function TTableRepairer.Matches(const AComments: TArray<TArray<string>>): TArray<Integer>;
var
  mTexts: TArray<string>;
  mEntry: Integer;
  mStrong: Boolean;
begin
  mTexts := DisplayTexts(FNames, FPrefix);
  SetLength(Result, FCount);
  for mEntry := 0 to FCount - 1 do
  begin
    Result[mEntry] := MatchOf(Entries(mEntry), AComments[mEntry], FNames, mTexts, FPrefix, mStrong);
    FLineComments := FLineComments or (mStrong and HasLineComment(AComments[mEntry]));
    // Jedes Element nur einmal.
    if UsedBefore(Result, mEntry) then
    begin
      Result[mEntry] := -1;
    end;
  end;
end;

procedure TTableRepairer.AddMissing(AFirstName, ALastName, AAfter, ANextEntry: Integer);
var
  mIndex, mNeighbor: Integer;
  mValues, mNames: TArray<string>;
begin
  mNeighbor := AAfter;
  if AAfter < 0 then
  begin
    mNeighbor := ANextEntry;
  end;
  mValues := nil;
  mNames := nil;
  for mIndex := AFirstName to ALastName do
  begin
    mValues := mValues + [ValueFor(FNames[mIndex], mNeighbor)];
    mNames := mNames + [FNames[mIndex]];
  end;
  FRepair.Added := FRepair.Added + mNames;
  Insert(AAfter, mValues, mNames);
end;

procedure TTableRepairer.RepairGap(APreviousName, APreviousEntry, ANextName, ANextEntry: Integer);
var
  mKept, mMissing: Integer;
begin
  mKept := ANextEntry - APreviousEntry - 1;
  mMissing := ANextName - APreviousName - 1;
  if (mKept > 0) and (mMissing > 0) and (mKept <> mMissing) then
  begin
    FRepair.Uncertain := True;
  end;
  if mMissing > mKept then
  begin
    AddMissing(APreviousName + 1 + mKept, ANextName - 1, APreviousEntry + mKept, ANextEntry);
  end
  else if mKept > mMissing then
  begin
    Remove(APreviousEntry + 1 + mMissing, ANextEntry - 1);
  end;
end;

procedure TTableRepairer.RepairGaps(const AAligned: TArray<Integer>);
var
  mPreviousName, mPreviousEntry, mNextName, mNextEntry: Integer;
begin
  // Lücken zwischen zugeordneten Einträgen: der Reihe nach, Rest einfügen bzw. entfernen.
  mPreviousName := -1;
  mPreviousEntry := -1;
  while mPreviousEntry < FCount do
  begin
    mNextEntry := NextAligned(AAligned, mPreviousEntry);
    mNextName := Length(FNames);
    if mNextEntry < FCount then
    begin
      mNextName := AAligned[mNextEntry];
    end;
    RepairGap(mPreviousName, mPreviousEntry, mNextName, mNextEntry);
    mPreviousName := mNextName;
    mPreviousEntry := mNextEntry;
  end;
end;

function TTableRepairer.Run(out ARepair: TEnumTableRepair): Boolean;
var
  mAligned: TArray<Integer>;
  mResource: TPendingResource;
begin
  FRepair := Default(TEnumTableRepair);
  Result := (FValue.Kind = TSyntaxKind.ParenExpr) and (FCount > 0) and (FNames <> nil);
  if Result then
  begin
    FLines := TLineTable.Build(FText);
    FLineBreak := TTextLines.LineBreakOf(FText);
    FPrefix := TEnumTables.CommonPrefix(FNames);
    mAligned := Increasing(Matches(EntryComments));
    FMultiLine := IsMultiLine(FText, FValue);
    FIndent := '';
    if FMultiLine then
    begin
      FIndent := TTextLines.IndentOf(FText, At(Entries(1).StartOffset).Line);
    end;
    RepairGaps(mAligned);
    for mResource in FResources do
    begin
      AddEdit(mResource.Offset, mResource.Offset, mResource.Text);
    end;
    Result := FRepair.Edits <> nil;
  end;
  ARepair := FRepair;
end;

class function TEnumTables.Repair(const AText: string; ATree: TSyntaxTree; AValue: TSyntaxNode;
  const ANames: TArray<string>; const AValues: TEnumTableValues; out ARepair: TEnumTableRepair): Boolean;
var
  mRepairer: TTableRepairer;
begin
  mRepairer := TTableRepairer.Create(AText, ATree, AValue, ANames, AValues);
  try
    Result := mRepairer.Run(ARepair);
  finally
    mRepairer.Free;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Editing.EnumTables', cTexts);

end.
