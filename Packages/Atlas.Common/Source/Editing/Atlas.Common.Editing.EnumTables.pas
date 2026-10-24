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
  public const
    CreateTitle = 'Namenstabelle anlegen (%s)';
    CreateImplementationTitle = 'Namenstabelle anlegen, im implementation-Teil (%s)';
    SyncTitle = 'Tabellen von %s nachziehen';
    AddTitle = 'Fehlenden Eintrag ergänzen (%s)';
    AddManyTitle = 'Fehlende Einträge ergänzen (%s)';
    RemoveTitle = 'Überzähligen Eintrag entfernen (%s)';
    RemoveManyTitle = 'Überzählige Einträge entfernen (%d)';
    AdjustTitle = 'Tabelle an %s anpassen';
    UncertainSuffix = ', Stelle geschätzt';
    UncertainNote = 'Die Stelle ist geschätzt: Nicht jeder Eintrag lässt sich einem Element zuordnen; ' +
      'Kommentare wie {osPaid} machen sie sicher.';
  public
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
    /// <summary>Änderungen für die Tabelle AName; False mit Grund.</summary>
    class function CreateTable(const AText: string; ATree: TSyntaxTree; const APosition: TTextPosition;
      const AName: string; APlacement: TEnumTablePlacement; AResourceStrings: Boolean;
      out AEdits: TArray<TTextEdit>; out AReason: string): Boolean; static;
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
  Atlas.Common.Editing.ResourceStrings;

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
    Delete(Result, 1, 1);
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
    Result := Format(TEnumTables.AdjustTitle, [string.Join(', ', Added)])
  else if Length(Added) = 1 then
    Result := Format(TEnumTables.AddTitle, [Added[0]])
  else if Added <> nil then
    Result := Format(TEnumTables.AddManyTitle, [string.Join(', ', Added)])
  else if Length(Removed) = 1 then
    Result := Format(TEnumTables.RemoveTitle, [Removed[0]])
  else
    Result := Format(TEnumTables.RemoveManyTitle, [Length(Removed)]);
  if Uncertain then
    Result := Result + TEnumTables.UncertainSuffix;
end;

{ TEnumTables }

class function TEnumTables.CommonPrefix(const ANames: TArray<string>): string;
var
  Name: string;
  Length_, Index: Integer;
begin
  Result := '';
  if ANames = nil then
    Exit;
  // Kleinbuchstaben am Anfang des ersten Namens, dann kürzen, bis alle passen.
  Length_ := 0;
  while (Length_ < Length(ANames[0])) and ANames[0][Length_ + 1].IsLower do
    Inc(Length_);
  for Name in ANames do
  begin
    Index := 0;
    while (Index < Length_) and (Index < Length(Name)) and (Name[Index + 1] = ANames[0][Index + 1]) do
      Inc(Index);
    Length_ := Index;
  end;
  // Nach dem Präfix muss in jedem Namen noch etwas Großes folgen (osNew, nicht open/other).
  for Name in ANames do
    if (Length(Name) <= Length_) or not (Name[Length_ + 1].IsUpper or Name[Length_ + 1].IsDigit) then
      Exit;
  Result := Copy(ANames[0], 1, Length_);
end;

class function TEnumTables.DisplayText(const AName, APrefix: string): string;
var
  Rest, Word: string;
  Words: TArray<string>;
  Index, Start: Integer;

  function Breaks(AAt: Integer): Boolean;
  begin
    // Wortgrenze vor AAt: klein → groß, oder groß → groß+klein (HTTPError → HTTP Error), Unterstrich.
    Result := (Rest[AAt].IsUpper and (Rest[AAt - 1].IsLower or Rest[AAt - 1].IsDigit)) or
      (Rest[AAt].IsUpper and Rest[AAt - 1].IsUpper and (AAt < Length(Rest)) and Rest[AAt + 1].IsLower);
  end;

begin
  Rest := AName;
  if (APrefix <> '') and StartsStr(APrefix, Rest) then
    Delete(Rest, 1, Length(APrefix));
  Rest := StringReplace(Rest, '_', ' ', [rfReplaceAll]);
  Words := nil;
  Start := 1;
  for Index := 2 to Length(Rest) do
    if (Rest[Index] <> ' ') and (Rest[Index - 1] <> ' ') and Breaks(Index) then
    begin
      Words := Words + [Copy(Rest, Start, Index - Start)];
      Start := Index;
    end;
  Words := Words + [Copy(Rest, Start, MaxInt)];
  Result := '';
  for Index := 0 to High(Words) do
  begin
    Word := Trim(Words[Index]);
    if Word = '' then
      Continue;
    // Abkürzungen (HTTP) bleiben groß, sonst nur das erste Wort mit großem Anfang.
    if (Length(Word) = 1) or (UpperCase(Word) <> Word) then
    begin
      if Result = '' then
        Word := UpperCase(Copy(Word, 1, 1)) + LowerCase(Copy(Word, 2, MaxInt))
      else
        Word := LowerCase(Word);
    end;
    if Result <> '' then
      Result := Result + ' ';
    Result := Result + Word;
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
    Delete(Rest, 1, Length(APrefix));
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
      Exit(False);
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
        Exit(TSyntaxSearchStep.Skip);
      if (ANode.Kind = TSyntaxKind.TypeDecl) and (ANode.FindChild(TSyntaxKind.EnumType) <> nil) then
        Exit(TSyntaxSearchStep.Found);
      Result := TSyntaxSearchStep.Descend;
    end);
  if Decl = nil then
    Exit(Fail('Kein Aufzählungstyp an dieser Stelle', AReason));
  Enum := Decl.FindChild(TSyntaxKind.EnumType);
  // Nur Typen der Unit: In Klassen und Routinen fehlt der Platz für eine Konstante dahinter.
  if (Decl.Parent = nil) or (Decl.Parent.Kind <> TSyntaxKind.TypeSection) or (Decl.Parent.Parent = nil) or
    not (Decl.Parent.Parent.Kind in [TSyntaxKind.InterfaceSection, TSyntaxKind.ImplementationSection,
    TSyntaxKind.ProgramFile, TSyntaxKind.LibraryFile]) then
    Exit(Fail(Format('%s steht nicht direkt im interface- oder implementation-Teil', [Decl.Name]), AReason));
  if not PlainNames(Enum, ATarget.Names) then
    Exit(Fail(Format('%s hat Elemente mit festen Werten; eine Tabelle darüber hätte Lücken', [Decl.Name]),
      AReason));
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
        Names := Names + [ANode.Name];
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
    if not (AName[Index].IsLetterOrDigit or (AName[Index] = '_')) then
      Exit(False);
end;

function Joined(const AHead: string; const AItems: TArray<string>; const AIndent, ALineBreak: string): string;
var
  Line: string;
  Index: Integer;
begin
  Line := AHead + '(' + string.Join(', ', AItems) + ');';
  if Length(AIndent + Line) <= LineLimit then
    Exit(AIndent + Line);
  Result := AIndent + AHead + '(';
  for Index := 0 to High(AItems) do
  begin
    Result := Result + ALineBreak + AIndent + '  ' + AItems[Index];
    if Index < High(AItems) then
      Result := Result + ',';
  end;
  Result := Result + ');';
end;

class function TEnumTables.CreateTable(const AText: string; ATree: TSyntaxTree; const APosition: TTextPosition;
  const AName: string; APlacement: TEnumTablePlacement; AResourceStrings: Boolean; out AEdits: TArray<TTextEdit>;
  out AReason: string): Boolean;
var
  Info: TEnumTarget;
  Decl, Section, Implementation_, UsesNode: TSyntaxNode;
  Lines: TLineTable;
  Taken, Items, Resources: TArray<string>;
  Prefix, LineBreak, Indent, Text, ResourceName_, Name: string;
  Offset, Index: Integer;
  Position: TTextPosition;
begin
  AEdits := nil;
  if not Target(ATree, APosition, Info, AReason) then
    Exit(False);
  if not IsIdentifier(AName) then
    Exit(Fail(Format('%s ist kein gültiger Name', [AName]), AReason));
  Taken := DeclaredNames(ATree);
  if IndexText(AName, Taken) >= 0 then
    Exit(Fail(Format('Der Name %s ist schon vergeben', [AName]), AReason));
  Lines := TLineTable.Build(AText);
  LineBreak := TTextLines.LineBreakOf(AText);
  Decl := ATree.Root.Search(
    function(ANode: TSyntaxNode): TSyntaxSearchStep
    begin
      if not Contains(ANode, APosition) then
        Exit(TSyntaxSearchStep.Skip);
      if (ANode.Kind = TSyntaxKind.TypeDecl) and (ANode.FindChild(TSyntaxKind.EnumType) <> nil) then
        Exit(TSyntaxSearchStep.Found);
      Result := TSyntaxSearchStep.Descend;
    end);
  Section := Decl.Parent;
  Indent := TTextLines.IndentOf(AText, Lines.PositionAt(Section.StartOffset).Line);
  Prefix := CommonPrefix(Info.Names);
  Items := nil;
  Resources := nil;
  for Name in Info.Names do
    if AResourceStrings then
    begin
      ResourceName_ := ResourceName(Info.TypeName, Name, Prefix);
      if IndexText(ResourceName_, Taken + Resources) >= 0 then
        Exit(Fail(Format('Der Name %s ist schon vergeben', [ResourceName_]), AReason));
      Resources := Resources + [ResourceName_];
      Items := Items + ['@' + ResourceName_];
    end
    else
      Items := Items + [QuotedStr(DisplayText(Name, Prefix))];
  Text := '';
  if AResourceStrings then
  begin
    Text := Indent + 'resourcestring';
    for Index := 0 to High(Resources) do
      Text := Text + LineBreak + Indent + '  ' + Resources[Index] + ' = ' +
        QuotedStr(DisplayText(Info.Names[Index], Prefix)) + ';';
    Text := Text + LineBreak + LineBreak + Indent + 'const' + LineBreak +
      Joined(AName + ': array[' + Info.TypeName + '] of PResStringRec = ', Items, Indent + '  ', LineBreak);
  end
  else
    Text := Indent + 'const' + LineBreak + Joined(AName + ': array[' + Info.TypeName + '] of string = ', Items,
      Indent + '  ', LineBreak);
  if (APlacement = TEnumTablePlacement.AfterType) or not Info.InInterface then
  begin
    // Direkt hinter der Deklaration; folgen im Abschnitt weitere Typen, beginnt für sie ein neuer.
    Offset := Lines.LineContentEnd(Lines.PositionAt(Decl.EndOffset).Line);
    Text := LineBreak + LineBreak + Text;
    if Section[Section.ChildCount - 1] <> Decl then
      Text := Text + LineBreak + LineBreak + Indent + 'type';
  end
  else
  begin
    Implementation_ := ATree.Root.FindChild(TSyntaxKind.ImplementationSection);
    if Implementation_ = nil then
      Exit(Fail('Die Unit hat keinen implementation-Teil', AReason));
    UsesNode := Implementation_.FindChild(TSyntaxKind.UsesClause);
    if UsesNode <> nil then
      Offset := Lines.LineContentEnd(Lines.PositionAt(UsesNode.EndOffset).Line)
    else
      Offset := Lines.LineContentEnd(Lines.PositionAt(Implementation_.StartOffset).Line);
    Text := LineBreak + LineBreak + Text;
  end;
  Position := Lines.PositionAt(Offset);
  AEdits := [TTextEdit.Create(TTextRange.Create(Position, Position), Text)];
  Result := True;
end;

function TableOf(ANode: TSyntaxNode; out ATable: TEnumTable): Boolean;
var
  ArrayNode, Value: TSyntaxNode;
begin
  Result := False;
  ATable := Default(TEnumTable);
  if not (ANode.Kind in [TSyntaxKind.ConstDecl, TSyntaxKind.VarDecl]) then
    Exit;
  ArrayNode := ANode.FindChild(TSyntaxKind.ArrayType);
  Value := ANode.FindChild(TSyntaxKind.ParenExpr);
  // Eine Dimension über einen benannten Typ: array[TTyp] of X.
  if (ArrayNode = nil) or (Value = nil) or (ArrayNode.ChildCount <> 2) or
    (ArrayNode[0].Kind <> TSyntaxKind.TypeReference) or (ArrayNode[0].ChildCount > 0) then
    Exit;
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
        Found := Found + [Table];
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
    if Contains(Table.Decl, APosition) then
    begin
      ATable := Table;
      Exit(True);
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
    Result := TEnumTableElement.Text
  else if MatchText(Name, ['integer', 'cardinal', 'int64', 'uint64', 'byte', 'word', 'longint', 'longword',
    'shortint', 'smallint', 'nativeint', 'nativeuint', 'int8', 'int16', 'int32', 'uint8', 'uint16', 'uint32']) then
    Result := TEnumTableElement.Number
  else if MatchText(Name, ['double', 'single', 'extended', 'real', 'currency']) then
    Result := TEnumTableElement.Float
  else if MatchText(Name, ['boolean', 'bytebool', 'wordbool', 'longbool']) then
    Result := TEnumTableElement.Boolean_
  else if MatchText(Name, ['char', 'widechar', 'ansichar']) then
    Result := TEnumTableElement.Char_
  else if MatchText(Name, ['pointer', 'tclass', 'pchar', 'pansichar', 'pwidechar']) then
    Result := TEnumTableElement.Pointer_
  else if SameText(Name, 'presstringrec') then
    Result := TEnumTableElement.ResourceString_
  else
    Result := TEnumTableElement.Other;
end;

type
  /// <summary>Ein Kommentar zwischen zwei Einträgen.</summary>
  TGapComment = record
    Text: string;
    /// <summary>Gehört zum Eintrag davor (False: zum Eintrag danach).</summary>
    ToPrevious: Boolean;
    IsLine: Boolean;
  end;

/// <summary>Kommentare im Text zwischen zwei Einträgen [AStart, AStop); AHasPrevious/AHasNext: gibt es die Einträge
/// davor und danach. Vor dem Komma gehört ein Kommentar zum vorigen Eintrag, dahinter zum nächsten, außer es folgt
/// ein Zeilenumbruch vor dem nächsten Eintrag (Zeilenkommentar hinter "'New',").</summary>
function GapComments(const AText: string; AStart, AStop: Integer; AHasPrevious, AHasNext: Boolean;
  out AComma: Integer): TArray<TGapComment>;
var
  Index, Stop: Integer;
  Comment: TGapComment;
  AfterComma: Boolean;
begin
  Result := nil;
  AComma := -1;
  AfterComma := False;
  Index := AStart;
  while Index < AStop do
  begin
    Stop := -1;
    Comment := Default(TGapComment);
    if AText[Index + 1] = ',' then
    begin
      AComma := Index;
      AfterComma := True;
      Inc(Index);
      Continue;
    end;
    if AText[Index + 1] = '{' then
    begin
      Stop := PosEx('}', AText, Index + 2);
      if Stop = 0 then
        Stop := AStop;
    end
    else if (AText[Index + 1] = '(') and (Index + 1 < AStop) and (AText[Index + 2] = '*') then
    begin
      Stop := PosEx('*)', AText, Index + 3);
      if Stop = 0 then
        Stop := AStop
      else
        Inc(Stop);
    end
    else if (AText[Index + 1] = '/') and (Index + 1 < AStop) and (AText[Index + 2] = '/') then
    begin
      Stop := Index + 1;
      while (Stop < AStop) and not CharInSet(AText[Stop + 1], [#13, #10]) do
        Inc(Stop);
      Comment.IsLine := True;
    end;
    if Stop < 0 then
    begin
      Inc(Index);
      Continue;
    end;
    if Stop > AStop then
      Stop := AStop;
    Comment.Text := Copy(AText, Index + 1, Stop - Index);
    if not AHasNext then
      Comment.ToPrevious := True
    else if not AHasPrevious then
      Comment.ToPrevious := False
    else if not AfterComma then
      Comment.ToPrevious := True
    else
      Comment.ToPrevious := (PosEx(#10, Copy(AText, Stop + 1, AStop - Stop)) > 0) or
        (Pos(#13, Copy(AText, Stop + 1, AStop - Stop)) > 0);
    Result := Result + [Comment];
    Index := Stop;
  end;
end;

function HasWord(const AText, AWord: string): Boolean;
var
  Index: Integer;
begin
  Index := Pos(LowerCase(AWord), LowerCase(AText));
  while Index > 0 do
  begin
    if ((Index = 1) or not (AText[Index - 1].IsLetterOrDigit or (AText[Index - 1] = '_'))) and
      ((Index + Length(AWord) > Length(AText)) or not (AText[Index + Length(AWord)].IsLetterOrDigit or
      (AText[Index + Length(AWord)] = '_'))) then
      Exit(True);
    Index := PosEx(LowerCase(AWord), LowerCase(AText), Index + 1);
  end;
  Result := False;
end;

function LiteralText(ANode: TSyntaxNode; out AValue: string): Boolean;
begin
  Result := (ANode.Kind = TSyntaxKind.Literal) and (Length(ANode.Name) >= 2) and (ANode.Name[1] = '''') and
    (ANode.Name[Length(ANode.Name)] = '''');
  if Result then
    AValue := StringReplace(Copy(ANode.Name, 2, Length(ANode.Name) - 2), '''''', '''', [rfReplaceAll]);
end;

/// <summary>Element, zu dem der Eintrag AEntry passt; -1 ohne. AStrong: über einen Kommentar.</summary>
function MatchOf(AEntry: TSyntaxNode; const AComments: TArray<string>; const ANames, ATexts: TArray<string>;
  const APrefix: string; out AStrong: Boolean): Integer;
var
  Index, Best, BestLength: Integer;
  Comment, Value, Identifier, Rest: string;
  Candidates: TArray<TSyntaxNode>;
  Candidate: TSyntaxNode;
begin
  AStrong := True;
  for Comment in AComments do
    for Index := 0 to High(ANames) do
      if HasWord(Comment, ANames[Index]) then
        Exit(Index);
  AStrong := False;
  // Texte im Eintrag selbst oder in einem Record (A: 'Neu'; B: 1).
  Candidates := [AEntry];
  if AEntry.Kind = TSyntaxKind.ParenExpr then
    for Index := 0 to AEntry.ChildCount - 1 do
      Candidates := Candidates + [AEntry[Index]];
  for Candidate in Candidates do
    if LiteralText(Candidate, Value) then
      for Index := 0 to High(ANames) do
        if SameText(Trim(Value), ATexts[Index]) or SameText(Trim(Value), ANames[Index]) then
          Exit(Index);
  // Bezeichner: @SOrderStatePaid, osPaid.
  Identifier := '';
  if (AEntry.Kind = TSyntaxKind.AddressOf) and (AEntry.ChildCount = 1) and
    (AEntry[0].Kind = TSyntaxKind.Identifier) then
    Identifier := AEntry[0].Name
  else if AEntry.Kind = TSyntaxKind.Identifier then
    Identifier := AEntry.Name;
  if Identifier = '' then
    Exit(-1);
  Best := -1;
  BestLength := 0;
  for Index := 0 to High(ANames) do
  begin
    if SameText(Identifier, ANames[Index]) then
      Exit(Index);
    Rest := Copy(ANames[Index], Length(APrefix) + 1, MaxInt);
    if (Rest <> '') and EndsText(Rest, Identifier) and (Length(Rest) > BestLength) then
    begin
      Best := Index;
      BestLength := Length(Rest);
    end;
  end;
  Result := Best;
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
      Continue;
    Lengths[Index] := 1;
    for Earlier := 0 to Index - 1 do
      if (AMatches[Earlier] >= 0) and (AMatches[Earlier] < AMatches[Index]) and
        (Lengths[Earlier] + 1 > Lengths[Index]) then
      begin
        Lengths[Index] := Lengths[Earlier] + 1;
        Previous[Index] := Earlier;
      end;
    if (Best < 0) or (Lengths[Index] > Lengths[Best]) then
      Best := Index;
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
    Dec(Index);
  Result := (Index = 0) or CharInSet(AText[Index], [#13, #10]);
end;

/// <summary>resourcestring-Deklaration namens AName in ATree; nil ohne.</summary>
function ResourceDecl(ATree: TSyntaxTree; const AName: string): TSyntaxNode;
begin
  Result := nil;
  if ATree = nil then
    Exit;
  Result := ATree.Root.Search(
    function(ANode: TSyntaxNode): TSyntaxSearchStep
    begin
      if (ANode.Kind = TSyntaxKind.ConstDecl) and SameText(ANode.Name, AName) and (ANode.Parent <> nil) and
        SameText(ANode.Parent.Name, 'resourcestring') then
        Exit(TSyntaxSearchStep.Found);
      if ANode.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.TypeDecl, TSyntaxKind.ConstDecl] then
        Exit(TSyntaxSearchStep.Skip);
      Result := TSyntaxSearchStep.Descend;
    end);
end;

class function TEnumTables.Repair(const AText: string; ATree: TSyntaxTree; AValue: TSyntaxNode;
  const ANames: TArray<string>; const AValues: TEnumTableValues; out ARepair: TEnumTableRepair): Boolean;
var
  Lines: TLineTable;
  Count, Total, Index, Entry, Gap, PreviousName, PreviousEntry, NextName, NextEntry, Kept, Missing, Comma: Integer;
  Prefix, LineBreak, Indent, Value, ResourceName_: string;
  Texts, Comments, NewValues: TArray<string>;
  EntryComments: TArray<TArray<string>>;
  Matches, Aligned: TArray<Integer>;
  LineComments, MultiLine, Strong: Boolean;
  Gaps: TArray<TGapComment>;
  GapComment: TGapComment;
  Taken: TArray<string>;
  ResourceNode: TSyntaxNode;
  ResourceIndent: string;
  /// <summary>Neue resourcestrings je Stelle, gesammelt, damit mehrere an derselben Stelle in Reihenfolge stehen.
  /// </summary>
  ResourceOffsets: TArray<Integer>;
  ResourceTexts: TArray<string>;

  function Entries(AIndex: Integer): TSyntaxNode;
  begin
    Result := AValue[AIndex];
  end;

  function At(AOffset: Integer): TTextPosition;
  begin
    Result := Lines.PositionAt(AOffset);
  end;

  procedure AddEdit(AStart, AStop: Integer; const ANewText: string);
  begin
    ARepair.Edits := ARepair.Edits + [TTextEdit.Create(TTextRange.Create(At(AStart), At(AStop)), ANewText)];
  end;

  procedure AddResource(AOffset: Integer; const ANewText: string);
  var
    Item: Integer;
  begin
    for Item := 0 to High(ResourceOffsets) do
      if ResourceOffsets[Item] = AOffset then
      begin
        ResourceTexts[Item] := ResourceTexts[Item] + ANewText;
        Exit;
      end;
    ResourceOffsets := ResourceOffsets + [AOffset];
    ResourceTexts := ResourceTexts + [ANewText];
  end;

  function ValueFor(const AName: string; ANeighbor: Integer): string;
  var
    Todo: string;
  begin
    Todo := ' {TODO ' + AName + '}';
    case AValues.Element of
      TEnumTableElement.Text:
        Result := QuotedStr(DisplayText(AName, Prefix));
      TEnumTableElement.Number:
        Result := '0' + Todo;
      TEnumTableElement.Float:
        Result := '0.0' + Todo;
      TEnumTableElement.Boolean_:
        Result := 'False' + Todo;
      TEnumTableElement.Char_:
        Result := '#0' + Todo;
      TEnumTableElement.Pointer_:
        Result := 'nil' + Todo;
      TEnumTableElement.Enum:
        Result := 'Low(' + AValues.ElementType + ')' + Todo;
      TEnumTableElement.ResourceString_:
        begin
          // Neuer resourcestring hinter dem des Nachbarn; ohne ihn ein nil-Platzhalter.
          ResourceNode := nil;
          if (ANeighbor >= 0) and (Entries(ANeighbor).Kind = TSyntaxKind.AddressOf) and
            (Entries(ANeighbor).ChildCount = 1) then
            ResourceNode := ResourceDecl(ATree, Entries(ANeighbor)[0].Name);
          if ResourceNode = nil then
            Exit('nil' + Todo);
          if Taken = nil then
            Taken := DeclaredNames(ATree);
          ResourceName_ := TResourceStrings.UniqueName(ResourceName(AValues.IndexType, AName, Prefix), Taken);
          Taken := Taken + [ResourceName_];
          ResourceIndent := TTextLines.IndentOf(AText, At(ResourceNode.StartOffset).Line);
          AddResource(Lines.LineContentEnd(At(ResourceNode.EndOffset).Line), LineBreak + ResourceIndent +
            ResourceName_ + ' = ' + QuotedStr(DisplayText(AName, Prefix)) + ';');
          Result := '@' + ResourceName_;
        end;
    else
      // Kopie des Nachbarn als Muster (Records, eigene Typen).
      if ANeighbor >= 0 then
        Result := Copy(AText, Entries(ANeighbor).StartOffset + 1, Entries(ANeighbor).EndOffset -
          Entries(ANeighbor).StartOffset) + Todo
      else
        Result := 'Default' + Todo;
    end;
  end;

  function WithComment(const AText_, AName: string): string;
  begin
    Result := AText_;
    if LineComments and MultiLine then
      Result := Result + ' // ' + AName;
  end;

  /// <summary>Fügt die Werte ANew nach dem Eintrag AAfter (-1: vor dem ersten) ein.</summary>
  procedure Insert(AAfter: Integer; const ANew, ANewNames: TArray<string>);
  var
    Item: Integer;
    Text_, Close: string;
    LineEnd, CloseOffset: Integer;
  begin
    if not MultiLine then
    begin
      if AAfter >= 0 then
        AddEdit(Entries(AAfter).EndOffset, Entries(AAfter).EndOffset, ', ' + string.Join(', ', ANew))
      else
        AddEdit(Entries(0).StartOffset, Entries(0).StartOffset, string.Join(', ', ANew) + ', ');
      Exit;
    end;
    if (AAfter >= 0) and (AAfter < Count - 1) then
    begin
      // Vor die Zeile des nächsten Eintrags.
      Text_ := '';
      for Item := 0 to High(ANew) do
        Text_ := Text_ + Indent + WithComment(ANew[Item] + ',', ANewNames[Item]) + LineBreak;
      AddEdit(Lines.LineStart(At(Entries(AAfter + 1).StartOffset).Line),
        Lines.LineStart(At(Entries(AAfter + 1).StartOffset).Line), Text_);
    end
    else if AAfter < 0 then
    begin
      Text_ := '';
      for Item := 0 to High(ANew) do
        Text_ := Text_ + WithComment(ANew[Item] + ',', ANewNames[Item]) + LineBreak + Indent;
      if StartsLine(AText, Entries(0).StartOffset) then
        AddEdit(Lines.LineStart(At(Entries(0).StartOffset).Line), Lines.LineStart(At(Entries(0).StartOffset).Line),
          Indent + Copy(Text_, 1, Length(Text_) - Length(Indent)))
      else
        AddEdit(Entries(0).StartOffset, Entries(0).StartOffset, Text_);
    end
    else
    begin
      // Hinter den letzten Eintrag: Komma an ihn, neue Zeilen dahinter.
      CloseOffset := AValue.EndOffset - 1;
      LineEnd := Lines.LineContentEnd(At(Entries(AAfter).EndOffset).Line);
      if CloseOffset < LineEnd then
      begin
        Text_ := '';
        for Item := 0 to High(ANew) do
          Text_ := Text_ + ',' + LineBreak + Indent + ANew[Item];
        AddEdit(Entries(AAfter).EndOffset, Entries(AAfter).EndOffset, Text_);
      end
      else
      begin
        Text_ := '';
        for Item := 0 to High(ANew) do
        begin
          Close := '';
          if Item < High(ANew) then
            Close := ',';
          Text_ := Text_ + LineBreak + Indent + WithComment(ANew[Item] + Close, ANewNames[Item]);
        end;
        // Ein Eintrag an derselben Stelle: Reihenfolge gleicher Stellen ist nicht festgelegt.
        if LineEnd = Entries(AAfter).EndOffset then
          AddEdit(LineEnd, LineEnd, ',' + Text_)
        else
        begin
          AddEdit(Entries(AAfter).EndOffset, Entries(AAfter).EndOffset, ',');
          AddEdit(LineEnd, LineEnd, Text_);
        end;
      end;
    end;
  end;

  /// <summary>Entfernt die Einträge AFirst..ALast.</summary>
  procedure Remove(AFirst, ALast: Integer);
  var
    Item, CommaAt: Integer;
  begin
    for Item := AFirst to ALast do
      ARepair.Removed := ARepair.Removed + [Copy(AText, Entries(Item).StartOffset + 1, Entries(Item).EndOffset -
        Entries(Item).StartOffset)];
    if ALast < Count - 1 then
    begin
      if MultiLine and StartsLine(AText, Entries(AFirst).StartOffset) then
        AddEdit(Lines.LineStart(At(Entries(AFirst).StartOffset).Line),
          Lines.LineStart(At(Entries(ALast + 1).StartOffset).Line), '')
      else
        AddEdit(Entries(AFirst).StartOffset, Entries(ALast + 1).StartOffset, '');
      Exit;
    end;
    // Am Ende: das Komma hinter dem vorigen Eintrag fällt mit weg.
    GapComments(AText, Entries(AFirst - 1).EndOffset, Entries(AFirst).StartOffset, True, True, CommaAt);
    if not MultiLine or (CommaAt < 0) then
    begin
      AddEdit(Entries(AFirst - 1).EndOffset, Entries(ALast).EndOffset, '');
      Exit;
    end;
    AddEdit(CommaAt, CommaAt + 1, '');
    if (AValue.EndOffset - 1) < Lines.LineContentEnd(At(Entries(ALast).EndOffset).Line) then
      AddEdit(Entries(AFirst).StartOffset, AValue.EndOffset - 1, '')
    else
      AddEdit(Lines.LineContentEnd(At(Entries(AFirst).StartOffset).Line - 1),
        Lines.LineContentEnd(At(Entries(ALast).EndOffset).Line), '');
  end;

begin
  ARepair := Default(TEnumTableRepair);
  Result := False;
  Count := AValue.ChildCount;
  Total := Length(ANames);
  if (AValue.Kind <> TSyntaxKind.ParenExpr) or (Count = 0) or (Total = 0) then
    Exit;
  ResourceOffsets := nil;
  ResourceTexts := nil;
  Taken := nil;
  Lines := TLineTable.Build(AText);
  LineBreak := TTextLines.LineBreakOf(AText);
  Prefix := CommonPrefix(ANames);
  Texts := nil;
  for Index := 0 to Total - 1 do
    Texts := Texts + [DisplayText(ANames[Index], Prefix)];
  // Kommentare je Eintrag.
  SetLength(EntryComments, Count);
  LineComments := False;
  for Gap := 0 to Count do
  begin
    if Gap = 0 then
      Gaps := GapComments(AText, AValue.StartOffset + 1, Entries(0).StartOffset, False, True, Comma)
    else if Gap = Count then
      Gaps := GapComments(AText, Entries(Count - 1).EndOffset, AValue.EndOffset - 1, True, False, Comma)
    else
      Gaps := GapComments(AText, Entries(Gap - 1).EndOffset, Entries(Gap).StartOffset, True, True, Comma);
    for GapComment in Gaps do
      if GapComment.ToPrevious then
        EntryComments[Gap - 1] := EntryComments[Gap - 1] + [GapComment.Text]
      else
        EntryComments[Gap] := EntryComments[Gap] + [GapComment.Text];
  end;
  SetLength(Matches, Count);
  for Entry := 0 to Count - 1 do
  begin
    Matches[Entry] := MatchOf(Entries(Entry), EntryComments[Entry], ANames, Texts, Prefix, Strong);
    if Strong then
      for Value in EntryComments[Entry] do
        if StartsStr('//', Value) then
          LineComments := True;
    // Jedes Element nur einmal.
    for Index := 0 to Entry - 1 do
      if (Matches[Entry] >= 0) and (Matches[Index] = Matches[Entry]) then
        Matches[Entry] := -1;
  end;
  Aligned := Increasing(Matches);
  MultiLine := Count >= 2;
  for Entry := 1 to Count - 1 do
    if not StartsLine(AText, Entries(Entry).StartOffset) then
      MultiLine := False;
  Indent := '';
  if MultiLine then
    Indent := TTextLines.IndentOf(AText, At(Entries(1).StartOffset).Line);
  // Lücken zwischen zugeordneten Einträgen: der Reihe nach, Rest einfügen bzw. entfernen.
  PreviousName := -1;
  PreviousEntry := -1;
  Entry := 0;
  while PreviousEntry < Count do
  begin
    NextEntry := PreviousEntry + 1;
    while (NextEntry < Count) and (Aligned[NextEntry] < 0) do
      Inc(NextEntry);
    if NextEntry < Count then
      NextName := Aligned[NextEntry]
    else
      NextName := Total;
    Kept := NextEntry - PreviousEntry - 1;
    Missing := NextName - PreviousName - 1;
    if (Kept > 0) and (Missing > 0) and (Kept <> Missing) then
      ARepair.Uncertain := True;
    if Missing > Kept then
    begin
      NewValues := nil;
      Comments := nil;
      for Index := PreviousName + 1 + Kept to NextName - 1 do
      begin
        if PreviousEntry + Kept >= 0 then
          Entry := PreviousEntry + Kept
        else
          Entry := NextEntry;
        NewValues := NewValues + [ValueFor(ANames[Index], Entry)];
        Comments := Comments + [ANames[Index]];
        ARepair.Added := ARepair.Added + [ANames[Index]];
      end;
      Insert(PreviousEntry + Kept, NewValues, Comments);
    end
    else if Kept > Missing then
      Remove(PreviousEntry + 1 + Missing, NextEntry - 1);
    PreviousName := NextName;
    PreviousEntry := NextEntry;
  end;
  for Index := 0 to High(ResourceOffsets) do
    AddEdit(ResourceOffsets[Index], ResourceOffsets[Index], ResourceTexts[Index]);
  Result := ARepair.Edits <> nil;
end;

end.
