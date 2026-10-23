unit Atlas.Common.Editing.MoveClass;

// „Klasse in eigene Unit verschieben“ (#103 Teil B): Die Deklaration einer
// Klasse (oder eines Records) samt Attributen, Doku-Kommentar, Vorwärts-
// deklaration und allen Methodenrümpfen kommt in eine neue Unit.
//
// Die uses der neuen Unit entstehen aus den Bezeichnern, die der verschobene
// Code braucht: Was die Deklaration braucht, steht im interface, was nur die
// Rümpfe brauchen, im implementation. Braucht die Klasse Namen aus dem
// interface der Ursprungs-Unit, bindet die neue Unit diese ein; die Ursprungs-
// Unit erhält die neue Unit im uses des Abschnitts, in dem sie die Klasse
// noch verwendet.
//
// Nicht angeboten: Zugriff auf Namen aus dem implementation-Teil der
// Ursprungs-Unit, Kreisverweis zweier interface-Teile, Formularklassen,
// gleichnamige generische Typen, bedingte Übersetzung um die verschobenen
// Teile, ein Ergebnis, das nicht parst.
//
// Bezeichner ohne Namensauflösung (Lookup nil oder unbekannter Name): lokale
// Namen und Mitglieder der Klasse kennt die Unit selbst, ebenso die Namen der
// Ursprungs-Unit; für alles andere übernimmt die neue Unit die uses der
// Ursprungs-Unit.

interface

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree;

type
  /// <summary>Bedeutung eines Namens an einer Stelle der Ursprungs-Unit.</summary>
  TMoveClassMeaning = record
    Found: Boolean;
    /// <summary>Lokale Variable, Parameter, Typparameter: braucht kein uses.</summary>
    IsLocal: Boolean;
    /// <summary>Unit der Deklaration; '' ohne (eingebaute Namen).</summary>
    UnitName: string;
    /// <summary>Datei und Stelle der Deklaration.</summary>
    FileName: string;
    Position: TTextPosition;
  end;

  /// <summary>Löst ANames (z. B. ['System', 'Classes', 'TList']) an AOffset der Ursprungs-Unit auf.</summary>
  TMoveClassLookup = reference to function(ATree: TSyntaxTree; const AFileName: string;
    const ANames: TArray<string>; AOffset: Integer): TMoveClassMeaning;

  TMoveClassPlan = record
    ClassName: string;
    OriginUnit: string;
    NewUnit: string;
    /// <summary>Text der neuen Unit, Zeilenenden wie die Ursprungs-Unit.</summary>
    Text: string;
    /// <summary>Änderungen an der Ursprungs-Unit.</summary>
    OriginEdits: TArray<TTextEdit>;
    /// <summary>Die neue Unit bindet die Ursprungs-Unit ein.</summary>
    UsesOrigin: Boolean;
    /// <summary>Namen ohne bekannte Unit: Für sie übernimmt die neue Unit die uses der Ursprungs-Unit.</summary>
    Unresolved: TArray<string>;
  end;

  TMoveClass = class
  public const
    Kind = 'refactor.move';
  public
    /// <summary>Klassen- oder Record-Deklaration, auf deren erster Zeile APosition steht; nil ohne.</summary>
    class function ClassAt(ATree: TSyntaxTree; const APosition: TTextPosition): TSyntaxNode; static;
    /// <summary>Vorgeschlagener Unit-Name: Klassenname ohne führendes T (TKunde → Kunde).</summary>
    class function DefaultUnitName(const AClassName: string): string; static;
    /// <summary>Neue Unit und Änderungen an der Ursprungs-Unit; False mit Grund, wenn nicht verschiebbar.</summary>
    class function Plan(const AFileName, AText: string; ATree: TSyntaxTree; const APosition: TTextPosition;
      const ANewUnit: string; const ALookup: TMoveClassLookup; out APlan: TMoveClassPlan;
      out AReason: string): Boolean; static;
    /// <summary>Änderungen an einer Unit, die die Klasse verwendet: qualifizierte Namen (Alt.TKunde) auf die neue
    /// Unit umstellen und, mit AAddUses, die neue Unit neben die Ursprungs-Unit ins uses. AReferences: Stellen
    /// aus der Referenzsuche; leer = jedes Vorkommen des Namens. False ohne Änderung.</summary>
    class function UpdateUser(const AText: string; ATree: TSyntaxTree; const AOriginUnit, ANewUnit,
      AClassName: string; const AReferences: TArray<TTextRange>; AAddUses: Boolean;
      out AEdits: TArray<TTextEdit>): Boolean; static;
  end;

implementation

uses
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Text.Lines,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Editing.RoutineBody,
  Atlas.Common.Editing.UsesClause,
  Atlas.Common.Editing.ChangeSignature;

const
  /// <summary>Namen aus System, die jede Unit ohne uses kennt; gelten auch ohne Namensauflösung als bekannt.
  /// </summary>
  SystemNames: array[0..93] of string = ('string', 'Integer', 'Cardinal', 'ShortInt', 'SmallInt', 'LongInt',
    'Int64', 'Byte', 'Word', 'LongWord', 'UInt64', 'NativeInt', 'NativeUInt', 'Boolean', 'ByteBool', 'WordBool',
    'LongBool', 'Char', 'AnsiChar', 'WideChar', 'Single', 'Double', 'Extended', 'Real', 'Currency', 'Comp',
    'Pointer', 'PChar', 'AnsiString', 'WideString', 'UnicodeString', 'ShortString', 'RawByteString', 'UTF8String',
    'Variant', 'OleVariant', 'TObject', 'TClass', 'IInterface', 'IUnknown', 'TGUID', 'TArray', 'TDateTime',
    'True', 'False', 'Exit', 'Inc', 'Dec', 'Length', 'SetLength', 'High', 'Low', 'Ord', 'Chr', 'Assigned', 'Copy',
    'Pos', 'Insert', 'Delete', 'Trunc', 'Round', 'Abs', 'Sqr', 'SizeOf', 'Default', 'New', 'Dispose', 'FreeMem',
    'GetMem', 'Move', 'FillChar', 'Include', 'Exclude', 'Succ', 'Pred', 'Odd', 'Assert', 'Break', 'Continue',
    'Halt', 'TypeInfo', 'Write', 'Writeln', 'Read', 'Readln', 'Concat', 'Str', 'Val', 'Random', 'Randomize',
    'Initialize', 'Finalize', 'IsManagedType', 'GetTypeKind');

type
  TOffsetRange = record
    Start: Integer;
    Stop: Integer;
  end;

function Fail(const AReason: string; out AOut: string): Boolean;
begin
  AOut := AReason;
  Result := False;
end;

function CleanName(const AName: string): string;
begin
  Result := AName;
  if Result.StartsWith('&') then
    Result := Result.Substring(1);
end;

function MakeRange(AStart, AStop: Integer): TOffsetRange;
begin
  Result.Start := AStart;
  Result.Stop := AStop;
end;

function InRanges(const ARanges: TArray<TOffsetRange>; AOffset: Integer): Boolean;
var
  Item: TOffsetRange;
begin
  for Item in ARanges do
    if (AOffset >= Item.Start) and (AOffset < Item.Stop) then
      Exit(True);
  Result := False;
end;

/// <summary>Typknoten einer Typdeklaration (ohne GenericParams); nil ohne.</summary>
function TypeNodeOf(ADecl: TSyntaxNode): TSyntaxNode;
var
  Index: Integer;
begin
  for Index := 0 to ADecl.ChildCount - 1 do
    if ADecl[Index].Kind <> TSyntaxKind.GenericParams then
      Exit(ADecl[Index]);
  Result := nil;
end;

function IsSection(ANode: TSyntaxNode): Boolean;
begin
  Result := (ANode <> nil) and (ANode.Kind in [TSyntaxKind.InterfaceSection, TSyntaxKind.ImplementationSection]);
end;

function IsMethodOf(ARoutine: TSyntaxNode; const AClassName: string): Boolean;
begin
  Result := (ARoutine.Kind = TSyntaxKind.RoutineDecl) and StartsText(AClassName + '.', ARoutine.Name);
end;

function UpperDirective(const AToken: TPascalToken): string;
begin
  Result := UpperCase(AToken.Text);
  if Result.StartsWith('{$') then
    Result := Result.Substring(2)
  else if Result.StartsWith('(*$') then
    Result := Result.Substring(3)
  else
    Result := '';
end;

/// <summary>+1 öffnet, -1 schließt, 2 verzweigt ({$ELSE}); 0 sonst.</summary>
function ConditionalStep(const AToken: TPascalToken): Integer;
var
  Text: string;
begin
  Result := 0;
  if AToken.Kind <> TPascalTokenKind.Directive then
    Exit;
  Text := UpperDirective(AToken);
  if StartsText('IFDEF', Text) or StartsText('IFNDEF', Text) or StartsText('IFOPT', Text) or
    StartsText('IF ', Text) or StartsText('IF(', Text) then
    Result := 1
  else if StartsText('ENDIF', Text) or StartsText('IFEND', Text) then
    Result := -1
  else if StartsText('ELSE', Text) then
    Result := 2;
end;

/// <summary>Steht ARange außerhalb jeder bedingten Übersetzung und sind die Direktiven darin ausgeglichen?</summary>
function Unconditional(const ATokens: TArray<TPascalToken>; const ARange: TOffsetRange): Boolean;
var
  Index, Depth, Step: Integer;
  Inside: Boolean;
begin
  Depth := 0;
  for Index := 0 to High(ATokens) do
  begin
    if ATokens[Index].Offset >= ARange.Stop then
      Break;
    Inside := ATokens[Index].Offset >= ARange.Start;
    if Inside and (Depth > 0) then
      Exit(False);
    Step := ConditionalStep(ATokens[Index]);
    if Step = 1 then
      Inc(Depth)
    else if Step = -1 then
    begin
      Dec(Depth);
      if Inside and (Depth < 0) then
        Exit(False);
      if Depth < 0 then
        Depth := 0;
    end
    else if (Step = 2) and Inside and (Depth = 0) then
      Exit(False);
    if Inside and (Depth < 0) then
      Exit(False);
  end;
  Result := Depth = 0;
end;

/// <summary>Ist der Text zwischen AFrom und ATo nur Leerraum?</summary>
function Blank(const AText: string; AFrom, ATo: Integer): Boolean;
var
  Index: Integer;
begin
  for Index := AFrom + 1 to ATo do
    if not CharInSet(AText[Index], [' ', #9, #13, #10]) then
      Exit(False);
  Result := True;
end;

function BlankLine(const AText: string; const ALines: TLineTable; ALine: Integer): Boolean;
begin
  Result := (ALine >= 0) and (ALine < ALines.LineCount) and
    Blank(AText, ALines.LineStart(ALine), ALines.LineContentEnd(ALine));
end;

/// <summary>Beginn samt Kommentaren in den Zeilen direkt darüber.</summary>
function WithLeadingComments(const AText: string; const ALines: TLineTable; const ATokens: TArray<TPascalToken>;
  AStart: Integer): Integer;
var
  Index: Integer;
begin
  Result := AStart;
  Index := TRoutineBody.TokenAt(ATokens, AStart);
  if Index < 0 then
    Exit;
  while (Index > 0) and (ATokens[Index - 1].Kind = TPascalTokenKind.Comment) and
    (ATokens[Index - 1].EndPos.Line >= ALines.PositionAt(Result).Line - 1) and
    Blank(AText, ALines.LineStart(ATokens[Index - 1].StartPos.Line), ATokens[Index - 1].Offset) do
  begin
    Dec(Index);
    Result := ATokens[Index].Offset;
  end;
end;

/// <summary>Bereich zum Entfernen: ganze Zeilen, wenn das Stück allein darauf steht, samt einer Leerzeile
/// dahinter, wenn davor auch eine steht.</summary>
function RemovalRange(const AText: string; const ALines: TLineTable; const APiece: TOffsetRange): TOffsetRange;
var
  First, Last: Integer;
begin
  Result := APiece;
  First := ALines.PositionAt(APiece.Start).Line;
  Last := ALines.PositionAt(APiece.Stop).Line;
  if not Blank(AText, ALines.LineStart(First), APiece.Start) or
    not Blank(AText, APiece.Stop, ALines.LineContentEnd(Last)) then
    Exit;
  Result.Start := ALines.LineStart(First);
  Result.Stop := ALines.LineStart(Last + 1);
  if (Last + 1 < ALines.LineCount) and BlankLine(AText, ALines, First - 1) and BlankLine(AText, ALines, Last + 1) then
    Result.Stop := ALines.LineStart(Last + 2);
end;

/// <summary>Text eines Stücks ab Zeilenanfang (Einrückung bleibt), wenn davor nur Leerraum steht.</summary>
function PieceText(const AText: string; const ALines: TLineTable; const APiece: TOffsetRange): string;
var
  Start: Integer;
begin
  Start := ALines.LineStart(ALines.PositionAt(APiece.Start).Line);
  if not Blank(AText, Start, APiece.Start) then
    Start := APiece.Start;
  Result := Copy(AText, Start + 1, APiece.Stop - Start);
end;

procedure AddUnique(var AList: TArray<string>; const AName: string);
var
  Item: string;
begin
  for Item in AList do
    if SameText(Item, AName) then
      Exit;
  AList := AList + [AName];
end;

function Contains(const AList: TArray<string>; const AName: string): Boolean;
var
  Item: string;
begin
  for Item in AList do
    if SameText(Item, AName) then
      Exit(True);
  Result := False;
end;

/// <summary>Namen der Deklarationen auf oberster Ebene mit Offset (Typen, Aufzählungswerte, Konstanten,
/// Variablen, Routinen; ohne Methodenrümpfe).</summary>
procedure CollectTopLevel(ASection: TSyntaxNode; ANames: TDictionary<string, Integer>);
var
  Index, Inner, Item: Integer;
  Node, Child, TypeNode: TSyntaxNode;
  Name: string;
begin
  for Index := 0 to ASection.ChildCount - 1 do
  begin
    Node := ASection[Index];
    case Node.Kind of
      TSyntaxKind.TypeSection, TSyntaxKind.ConstSection, TSyntaxKind.VarSection:
        for Inner := 0 to Node.ChildCount - 1 do
        begin
          Child := Node[Inner];
          if not (Child.Kind in [TSyntaxKind.TypeDecl, TSyntaxKind.ConstDecl, TSyntaxKind.VarDecl]) then
            Continue;
          for Name in Child.Name.Split([',']) do
            if not ANames.ContainsKey(LowerCase(Trim(Name))) then
              ANames.Add(LowerCase(Trim(Name)), Child.StartOffset);
          if Child.Kind = TSyntaxKind.TypeDecl then
          begin
            TypeNode := TypeNodeOf(Child);
            if (TypeNode <> nil) and (TypeNode.Kind = TSyntaxKind.EnumType) then
              for Item := 0 to TypeNode.ChildCount - 1 do
                if (TypeNode[Item].Kind = TSyntaxKind.Identifier) and
                  not ANames.ContainsKey(LowerCase(TypeNode[Item].Name)) then
                  ANames.Add(LowerCase(TypeNode[Item].Name), TypeNode[Item].StartOffset);
          end;
        end;
      TSyntaxKind.RoutineDecl:
        if (Pos('.', Node.Name) = 0) and not ANames.ContainsKey(LowerCase(Node.Name)) then
          ANames.Add(LowerCase(Node.Name), Node.StartOffset);
    else
      // Übrige Werte bewusst ohne Wirkung.
    end;
  end;
end;

/// <summary>Namen, die ohne uses bekannt sind: Mitglieder und Typparameter der Klasse, Parameter, Variablen
/// und Konstanten der Methoden samt Result und Self.</summary>
procedure CollectOwnNames(ANode: TSyntaxNode; ANames: TDictionary<string, Boolean>);
var
  Names: TDictionary<string, Boolean>;
begin
  Names := ANames;
  // Walk statt Rekursion (Bericht M1). Laufvariablen „for var I“ stehen als InlineVar im for.
  ANode.Walk(
    function(AChild: TSyntaxNode): Boolean
    var
      Index: Integer;
      Name: string;
    begin
      case AChild.Kind of
        TSyntaxKind.Field, TSyntaxKind.PropertyDecl, TSyntaxKind.RoutineHeader, TSyntaxKind.TypeDecl,
        TSyntaxKind.VarDecl, TSyntaxKind.ConstDecl, TSyntaxKind.Parameter, TSyntaxKind.InlineVar,
        TSyntaxKind.InlineConst, TSyntaxKind.RoutineDecl:
          for Name in AChild.Name.Split([',']) do
            if (Trim(Name) <> '') and (Pos('.', Name) = 0) then
              Names.AddOrSetValue(LowerCase(Trim(Name)), True);
        TSyntaxKind.GenericParams:
          for Index := 0 to AChild.ChildCount - 1 do
            Names.AddOrSetValue(LowerCase(AChild[Index].Name), True);
      else
        // Übrige Werte bewusst ohne Wirkung.
      end;
      Result := True;
    end);
end;

/// <summary>Name eines Attributs: [Weak] bzw. [Fixture('x')].</summary>
function IsAttributeName(ANode: TSyntaxNode): Boolean;
var
  Parent: TSyntaxNode;
begin
  Parent := ANode.Parent;
  Result := (ANode.Kind = TSyntaxKind.Identifier) and (Parent <> nil) and
    ((Parent.Kind = TSyntaxKind.Attribute) or ((Parent.Kind = TSyntaxKind.Call) and (Parent[0] = ANode) and
    (Parent.Parent <> nil) and (Parent.Parent.Kind = TSyntaxKind.Attribute)));
end;

type
  TNeed = record
    Names: TArray<string>;
    Node: TSyntaxNode;
  end;

procedure CollectNeeds(ANode: TSyntaxNode; var ANeeds: TArray<TNeed>);
var
  Needs: TList<TNeed>;
begin
  // Walk statt Rekursion (Bericht M1).
  Needs := TList<TNeed>.Create;
  try
    ANode.Walk(
      function(AChild: TSyntaxNode): Boolean
      var
        Need: TNeed;
      begin
        Need.Node := AChild;
        Need.Names := nil;
        case AChild.Kind of
          TSyntaxKind.Identifier:
            if (AChild.Parent = nil) or (AChild.Parent.Kind <> TSyntaxKind.GenericParams) then
              Need.Names := [CleanName(AChild.Name)];
          TSyntaxKind.TypeReference:
            if AChild.Name <> '' then
              Need.Names := AChild.Name.Split(['.']);
        else
          // Übrige Werte bewusst ohne Wirkung.
        end;
        if Need.Names <> nil then
          Needs.Add(Need);
        Result := True;
      end);
    ANeeds := ANeeds + Needs.ToArray;
  finally
    Needs.Free;
  end;
end;

/// <summary>Namen aller uses-Einträge eines Abschnitts.</summary>
function SectionUses(ASection: TSyntaxNode): TArray<string>;
var
  Index, Item: Integer;
begin
  Result := nil;
  if ASection = nil then
    Exit;
  for Index := 0 to ASection.ChildCount - 1 do
    if ASection[Index].Kind = TSyntaxKind.UsesClause then
      for Item := 0 to ASection[Index].ChildCount - 1 do
        AddUnique(Result, ASection[Index][Item].Name);
end;

/// <summary>Schreibweise aus den uses der Ursprungs-Unit (SysUtils statt System.SysUtils), sonst AUnit.</summary>
function Spelling(const AOriginUses: TArray<string>; const AUnit: string): string;
var
  Item: string;
begin
  for Item in AOriginUses do
    if SameText(Item, AUnit) or EndsText('.' + Item, AUnit) then
      Exit(Item);
  Result := AUnit;
end;

/// <summary>Reihenfolge wie in den uses der Ursprungs-Unit, fremde Units dahinter.</summary>
function Ordered(const AOriginUses, AUnits: TArray<string>): TArray<string>;
var
  Item: string;
begin
  Result := nil;
  for Item in AOriginUses do
    if Contains(AUnits, Item) then
      Result := Result + [Item];
  for Item in AUnits do
    AddUnique(Result, Item);
end;

function UsesText(const AUnits: TArray<string>; const ALineBreak: string): string;
begin
  Result := '';
  if AUnits = nil then
    Exit;
  Result := 'uses' + ALineBreak + '  ' + string.Join(',' + ALineBreak + '  ', AUnits) + ';' + ALineBreak +
    ALineBreak;
end;

/// <summary>Edit, das den Qualifizierer AOrigin vor dem Token an AIndex (Alt.TKunde) durch ANew ersetzt; False
/// ohne Qualifizierer.</summary>
function QualifierEdit(const ATokens: TArray<TPascalToken>; AIndex: Integer; const AOrigin, ANew: string;
  out AEdit: TTextEdit): Boolean;
var
  Parts: TArray<string>;
  Dot, Name, Part, Before: Integer;
begin
  Result := False;
  Parts := AOrigin.Split(['.']);
  Dot := TRoutineBody.PreviousToken(ATokens, AIndex);
  if (Dot < 0) or not ATokens[Dot].IsSymbol('.') then
    Exit;
  Name := Dot;
  for Part := High(Parts) downto 0 do
  begin
    if Part < High(Parts) then
    begin
      Name := TRoutineBody.PreviousToken(ATokens, Name);
      if (Name < 0) or not ATokens[Name].IsSymbol('.') then
        Exit;
    end;
    Name := TRoutineBody.PreviousToken(ATokens, Name);
    if (Name < 0) or (ATokens[Name].Kind <> TPascalTokenKind.Identifier) or
      not SameText(CleanName(ATokens[Name].Text), Parts[Part]) then
      Exit;
  end;
  // Steht davor ein weiterer Punkt, ist es ein Mitglied eines anderen Namens.
  Before := TRoutineBody.PreviousToken(ATokens, Name);
  if (Before >= 0) and ATokens[Before].IsSymbol('.') then
    Exit;
  AEdit := TTextEdit.Create(TTextRange.Create(ATokens[Name].StartPos, ATokens[Dot].StartPos), ANew);
  Result := True;
end;

{ TMoveClass }

class function TMoveClass.ClassAt(ATree: TSyntaxTree; const APosition: TTextPosition): TSyntaxNode;
var
  Section, Index, Item: Integer;
  Node, Decl, TypeNode: TSyntaxNode;
begin
  Result := nil;
  if (ATree = nil) or (ATree.Root = nil) or (ATree.Root.Kind <> TSyntaxKind.UnitFile) then
    Exit;
  for Section := 0 to ATree.Root.ChildCount - 1 do
  begin
    Node := ATree.Root[Section];
    if not IsSection(Node) then
      Continue;
    for Index := 0 to Node.ChildCount - 1 do
      if Node[Index].Kind = TSyntaxKind.TypeSection then
        for Item := 0 to Node[Index].ChildCount - 1 do
        begin
          Decl := Node[Index][Item];
          if (Decl.Kind <> TSyntaxKind.TypeDecl) or (Decl.StartPos.Line <> APosition.Line) then
            Continue;
          TypeNode := TypeNodeOf(Decl);
          if (TypeNode <> nil) and (TypeNode.Kind in [TSyntaxKind.ClassType, TSyntaxKind.RecordType]) then
            Exit(Decl);
        end;
  end;
end;

class function TMoveClass.DefaultUnitName(const AClassName: string): string;
begin
  Result := AClassName;
  if (Length(Result) > 1) and CharInSet(Result[1], ['T', 't']) and CharInSet(Result[2], ['A'..'Z']) then
    Result := Result.Substring(1);
end;

class function TMoveClass.Plan(const AFileName, AText: string; ATree: TSyntaxTree; const APosition: TTextPosition;
  const ANewUnit: string; const ALookup: TMoveClassLookup; out APlan: TMoveClassPlan; out AReason: string): Boolean;
var
  Lines: TLineTable;
  Decl, TypeNode, Section, InterfaceNode, ImplementationNode, Node, TypeSection: TSyntaxNode;
  Index, Item, Offset, ImplementationStart, Before: Integer;
  Methods, Forwards, Attributes: TArray<TSyntaxNode>;
  Moved, Removals: TArray<TOffsetRange>;
  DeclRange, Piece, Last: TOffsetRange;
  TopLevel: TDictionary<string, Integer>;
  Own: TDictionary<string, Boolean>;
  DeclNeeds, BodyNeeds, Needs: TArray<TNeed>;
  Need: TNeed;
  Meaning: TMoveClassMeaning;
  InDecl, DeclNeedsOrigin, BodyNeedsOrigin, UnknownInDecl, UnknownInBody, InterfaceRef, ImplementationRef,
    WholeSection: Boolean;
  OriginUses, InterfaceUses, ImplementationUses, DeclUnits, BodyUnits: TArray<string>;
  LineBreak, Ancestor, Name, Body, MethodsText, Applied: string;
  Edit: TTextEdit;
  Edits: TArray<TTextEdit>;
  Check: TSyntaxTree;
  Pass: Integer;
begin
  APlan := Default(TMoveClassPlan);
  AReason := '';
  Decl := ClassAt(ATree, APosition);
  if Decl = nil then
    Exit(Fail('keine Klasse an dieser Stelle', AReason));
  TypeNode := TypeNodeOf(Decl);
  TypeSection := Decl.Parent;
  Section := TypeSection.Parent;
  APlan.ClassName := CleanName(Decl.Name);
  APlan.OriginUnit := ATree.Root.Name;
  APlan.NewUnit := Trim(ANewUnit);
  if not IsValidIdent(APlan.NewUnit, True) then
    Exit(Fail(Format('„%s“ ist kein gültiger Unit-Name', [APlan.NewUnit]), AReason));
  if SameText(APlan.NewUnit, APlan.OriginUnit) then
    Exit(Fail('die neue Unit hieße wie die Ursprungs-Unit', AReason));
  InterfaceNode := ATree.Root.FindChild(TSyntaxKind.InterfaceSection);
  ImplementationNode := ATree.Root.FindChild(TSyntaxKind.ImplementationSection);
  if (InterfaceNode = nil) or (ImplementationNode = nil) then
    Exit(Fail('die Unit hat keinen interface- und implementation-Teil', AReason));
  ImplementationStart := ImplementationNode.StartOffset;
  Lines := TLineTable.Build(AText);
  LineBreak := TTextLines.LineBreakOf(AText);
  // Gleichnamige Typen und Vorwärtsdeklarationen.
  Forwards := nil;
  for Index := 0 to ATree.Root.ChildCount - 1 do
  begin
    Node := ATree.Root[Index];
    if not IsSection(Node) then
      Continue;
    for Item := 0 to Node.ChildCount - 1 do
      if Node[Item].Kind = TSyntaxKind.TypeSection then
        for Offset := 0 to Node[Item].ChildCount - 1 do
          if (Node[Item][Offset] <> Decl) and (Node[Item][Offset].Kind = TSyntaxKind.TypeDecl) and
            SameText(CleanName(Node[Item][Offset].Name), APlan.ClassName) then
          begin
            if (TypeNodeOf(Node[Item][Offset]) <> nil) and
              (TypeNodeOf(Node[Item][Offset]).Kind = TSyntaxKind.ForwardType) then
              Forwards := Forwards + [Node[Item][Offset]]
            else
              Exit(Fail(Format('mehrere Typen heißen %s', [APlan.ClassName]), AReason));
          end;
  end;
  // Formularklassen bleiben bei ihrer .dfm bzw. .fmx.
  if (TypeNode.Kind = TSyntaxKind.ClassType) and (TypeNode.ChildCount > 0) and
    (TypeNode[0].Kind = TSyntaxKind.TypeReference) then
  begin
    Ancestor := TypeNode[0].Name;
    if Pos('.', Ancestor) > 0 then
      Ancestor := Ancestor.Substring(Ancestor.LastIndexOf('.') + 1);
    if (ContainsText(AText, '{$R *.dfm}') or ContainsText(AText, '{$R *.fmx}') or
      ContainsText(AText, '{$R *.xfm}')) and (MatchText(Ancestor, ['TForm', 'TFrame', 'TDataModule']) or
      EndsText('Form', Ancestor) or EndsText('Frame', Ancestor)) then
      Exit(Fail('Formularklassen bleiben bei ihrer Formulardatei', AReason));
  end;
  // Attribute direkt davor gehören zur Deklaration.
  Attributes := nil;
  Index := -1;
  for Item := 0 to TypeSection.ChildCount - 1 do
    if TypeSection[Item] = Decl then
      Index := Item;
  while (Index > 0) and (TypeSection[Index - 1].Kind = TSyntaxKind.Attribute) do
  begin
    Dec(Index);
    Attributes := [TypeSection[Index]] + Attributes;
  end;
  DeclRange := MakeRange(Decl.StartOffset, Decl.EndOffset);
  if Attributes <> nil then
    DeclRange.Start := Attributes[0].StartOffset;
  DeclRange.Start := WithLeadingComments(AText, Lines, ATree.Tokens, DeclRange.Start);
  Methods := nil;
  for Index := 0 to ImplementationNode.ChildCount - 1 do
    if IsMethodOf(ImplementationNode[Index], APlan.ClassName) then
      Methods := Methods + [ImplementationNode[Index]];
  Moved := [DeclRange];
  for Node in Forwards do
    Moved := Moved + [MakeRange(WithLeadingComments(AText, Lines, ATree.Tokens, Node.StartOffset), Node.EndOffset)];
  for Node in Methods do
    Moved := Moved + [MakeRange(WithLeadingComments(AText, Lines, ATree.Tokens, Node.StartOffset), Node.EndOffset)];
  for Piece in Moved do
    if not Unconditional(ATree.Tokens, Piece) then
      Exit(Fail('ein Teil der Klasse steht in bedingter Übersetzung', AReason));
  // Benötigte Namen.
  DeclNeeds := nil;
  CollectNeeds(Decl, DeclNeeds);
  for Node in Attributes do
    CollectNeeds(Node, DeclNeeds);
  BodyNeeds := nil;
  for Node in Methods do
    CollectNeeds(Node, BodyNeeds);
  TopLevel := TDictionary<string, Integer>.Create;
  Own := TDictionary<string, Boolean>.Create;
  try
    CollectTopLevel(InterfaceNode, TopLevel);
    CollectTopLevel(ImplementationNode, TopLevel);
    CollectOwnNames(Decl, Own);
    for Node in Methods do
      CollectOwnNames(Node, Own);
    Own.AddOrSetValue('result', True);
    Own.AddOrSetValue('self', True);
    OriginUses := SectionUses(InterfaceNode) + SectionUses(ImplementationNode);
    DeclUnits := nil;
    BodyUnits := nil;
    DeclNeedsOrigin := False;
    BodyNeedsOrigin := False;
    UnknownInDecl := False;
    UnknownInBody := False;
    for Pass := 0 to 1 do
    begin
      InDecl := Pass = 0;
      Needs := BodyNeeds;
      if InDecl then
        Needs := DeclNeeds;
      for Need in Needs do
      begin
        Meaning := Default(TMoveClassMeaning);
        if Assigned(ALookup) then
          Meaning := ALookup(ATree, AFileName, Need.Names, Need.Node.StartOffset);
        Name := Need.Names[0];
        // Attribute: [Weak] meint WeakAttribute.
        if not Meaning.Found and Assigned(ALookup) and IsAttributeName(Need.Node) then
          Meaning := ALookup(ATree, AFileName, [Name + 'Attribute'], Need.Node.StartOffset);
        if not Meaning.Found then
        begin
          // Ohne Namensauflösung: eigene Namen, dann die der Ursprungs-Unit.
          if (Length(Need.Names) = 1) and (Own.ContainsKey(LowerCase(Name)) or MatchText(Name, SystemNames)) then
            Continue;
          if TopLevel.TryGetValue(LowerCase(Name), Offset) then
          begin
            Meaning.Found := True;
            Meaning.UnitName := APlan.OriginUnit;
            Meaning.FileName := AFileName;
            Meaning.Position := Lines.PositionAt(Offset);
          end
          else if SameText(Name, APlan.OriginUnit) then
            Continue
          else
          begin
            AddUnique(APlan.Unresolved, string.Join('.', Need.Names));
            if InDecl then
              UnknownInDecl := True
            else
              UnknownInBody := True;
            Continue;
          end;
        end;
        if Meaning.IsLocal or (Meaning.UnitName = '') or MatchText(Meaning.UnitName, ['System', 'SysInit']) then
          Continue;
        if SameText(Meaning.UnitName, APlan.OriginUnit) or
          ((Meaning.FileName <> '') and SameText(Meaning.FileName, AFileName)) then
        begin
          Offset := Lines.OffsetAt(Meaning.Position);
          if InRanges(Moved, Offset) then
            Continue;
          if Offset >= ImplementationStart then
            Exit(Fail(Format('die Klasse verwendet %s aus dem implementation-Teil von %s', [Name,
              APlan.OriginUnit]), AReason));
          if InDecl then
            DeclNeedsOrigin := True
          else
            BodyNeedsOrigin := True;
          Continue;
        end;
        if InDecl then
          AddUnique(DeclUnits, Spelling(OriginUses, Meaning.UnitName))
        else
          AddUnique(BodyUnits, Spelling(OriginUses, Meaning.UnitName));
      end;
    end;
  finally
    Own.Free;
    TopLevel.Free;
  end;
  // Verwendet die Ursprungs-Unit die Klasse noch?
  InterfaceRef := False;
  ImplementationRef := False;
  for Index := 0 to High(ATree.Tokens) do
    if (ATree.Tokens[Index].Kind = TPascalTokenKind.Identifier) and
      SameText(CleanName(ATree.Tokens[Index].Text), APlan.ClassName) and
      not InRanges(Moved, ATree.Tokens[Index].Offset) and (ATree.Tokens[Index].Offset >= InterfaceNode.StartOffset) then
    begin
      if ATree.Tokens[Index].Offset < ImplementationStart then
        InterfaceRef := True
      else
        ImplementationRef := True;
    end;
  if DeclNeedsOrigin and InterfaceRef then
    Exit(Fail(Format('Kreisverweis: die Klasse braucht Typen aus dem interface von %s, das sie selbst verwendet',
      [APlan.OriginUnit]), AReason));
  // uses der neuen Unit.
  InterfaceUses := DeclUnits;
  if UnknownInDecl then
  begin
    for Name in SectionUses(InterfaceNode) do
      AddUnique(InterfaceUses, Name);
    if Section = ImplementationNode then
      for Name in SectionUses(ImplementationNode) do
        AddUnique(InterfaceUses, Name);
  end;
  InterfaceUses := Ordered(OriginUses, InterfaceUses);
  if DeclNeedsOrigin then
    InterfaceUses := InterfaceUses + [APlan.OriginUnit];
  ImplementationUses := nil;
  for Name in BodyUnits do
    if not Contains(InterfaceUses, Name) then
      AddUnique(ImplementationUses, Name);
  if UnknownInBody then
    for Name in OriginUses do
      if not Contains(InterfaceUses, Name) then
        AddUnique(ImplementationUses, Name);
  ImplementationUses := Ordered(OriginUses, ImplementationUses);
  if BodyNeedsOrigin and not DeclNeedsOrigin then
    ImplementationUses := ImplementationUses + [APlan.OriginUnit];
  APlan.UsesOrigin := DeclNeedsOrigin or BodyNeedsOrigin;
  // Die neue Unit.
  MethodsText := '';
  for Node in Methods do
  begin
    Body := PieceText(AText, Lines, MakeRange(WithLeadingComments(AText, Lines, ATree.Tokens, Node.StartOffset),
      Node.EndOffset));
    if MethodsText <> '' then
      MethodsText := MethodsText + LineBreak + LineBreak;
    MethodsText := MethodsText + Body;
  end;
  if MethodsText <> '' then
    MethodsText := MethodsText + LineBreak + LineBreak;
  APlan.Text := 'unit ' + APlan.NewUnit + ';' + LineBreak + LineBreak + 'interface' + LineBreak + LineBreak +
    UsesText(InterfaceUses, LineBreak) + 'type' + LineBreak + PieceText(AText, Lines, DeclRange) + LineBreak +
    LineBreak + 'implementation' + LineBreak + LineBreak + UsesText(ImplementationUses, LineBreak) + MethodsText +
    'end.' + LineBreak;
  // Entfernen; ein Typabschnitt, der leer würde, entfällt ganz.
  WholeSection := True;
  for Index := 0 to TypeSection.ChildCount - 1 do
    if not InRanges(Moved, TypeSection[Index].StartOffset) then
      WholeSection := False;
  Removals := nil;
  if WholeSection then
    Removals := [MakeRange(WithLeadingComments(AText, Lines, ATree.Tokens, TypeSection.StartOffset),
      TypeSection.EndOffset)];
  for Piece in Moved do
    if not (WholeSection and (Piece.Start >= TypeSection.StartOffset) and (Piece.Stop <= TypeSection.EndOffset)) then
      Removals := Removals + [Piece];
  for Index := 0 to High(Removals) do
    Removals[Index] := RemovalRange(AText, Lines, Removals[Index]);
  // Sortieren und Überlappungen zusammenfassen.
  for Index := 1 to High(Removals) do
  begin
    Piece := Removals[Index];
    Item := Index - 1;
    while (Item >= 0) and (Removals[Item].Start > Piece.Start) do
    begin
      Removals[Item + 1] := Removals[Item];
      Dec(Item);
    end;
    Removals[Item + 1] := Piece;
  end;
  Edits := nil;
  Last := MakeRange(-1, -1);
  for Piece in Removals do
  begin
    if (Last.Start >= 0) and (Piece.Start <= Last.Stop) then
    begin
      if Piece.Stop > Last.Stop then
        Last.Stop := Piece.Stop;
      Continue;
    end;
    if Last.Start >= 0 then
      Edits := Edits + [TTextEdit.Create(TTextRange.Create(Lines.PositionAt(Last.Start), Lines.PositionAt(Last.Stop)),
        '')];
    Last := Piece;
  end;
  if Last.Start >= 0 then
    Edits := Edits + [TTextEdit.Create(TTextRange.Create(Lines.PositionAt(Last.Start), Lines.PositionAt(Last.Stop)),
      '')];
  // Die Ursprungs-Unit bindet die neue Unit ein, wo sie die Klasse noch verwendet.
  if InterfaceRef or ImplementationRef then
  begin
    if InterfaceRef then
      Offset := InterfaceNode.StartOffset
    else
      Offset := ImplementationStart;
    if not TUsesClauses.AddUnit(ATree.Tokens, Offset, APlan.NewUnit, LineBreak, Edit) then
      Exit(Fail('kein Platz für die neue Unit im uses', AReason));
    Edits := Edits + [Edit];
  end;
  for Index := 0 to High(ATree.Tokens) do
    if (ATree.Tokens[Index].Kind = TPascalTokenKind.Identifier) and
      SameText(CleanName(ATree.Tokens[Index].Text), APlan.ClassName) and
      not InRanges(Moved, ATree.Tokens[Index].Offset) and
      QualifierEdit(ATree.Tokens, Index, APlan.OriginUnit, APlan.NewUnit, Edit) then
      Edits := Edits + [Edit];
  APlan.OriginEdits := Edits;
  // Vorher fehlerfrei, nachher auch.
  Before := Length(ATree.Diagnostics);
  if Before = 0 then
  begin
    Applied := TChangeSignature.ApplyEdits(AText, Edits);
    Check := TSyntaxTreeCache.Parse(Applied);
    try
      if Length(Check.Diagnostics) > 0 then
        Exit(Fail('die Ursprungs-Unit parst danach nicht mehr', AReason));
    finally
      Check.Free;
    end;
    Check := TSyntaxTreeCache.Parse(APlan.Text);
    try
      if Length(Check.Diagnostics) > 0 then
        Exit(Fail('die neue Unit parst nicht', AReason));
    finally
      Check.Free;
    end;
  end;
  Result := True;
end;

class function TMoveClass.UpdateUser(const AText: string; ATree: TSyntaxTree; const AOriginUnit, ANewUnit,
  AClassName: string; const AReferences: TArray<TTextRange>; AAddUses: Boolean;
  out AEdits: TArray<TTextEdit>): Boolean;
var
  Index, First: Integer;
  Found: Boolean;
  Reference: TTextRange;
  Edit: TTextEdit;
  Clause: TUsesClauseInfo;
  Clauses: TArray<TUsesClauseInfo>;
  ShortName: string;
begin
  AEdits := nil;
  // Mit Namespace-Präfix des Projekts steht Firma.Lager als Lager im uses.
  ShortName := AOriginUnit;
  if Pos('.', ShortName) > 0 then
    ShortName := ShortName.Substring(ShortName.LastIndexOf('.') + 1);
  First := -1;
  for Index := 0 to High(ATree.Tokens) do
  begin
    if (ATree.Tokens[Index].Kind <> TPascalTokenKind.Identifier) or
      not SameText(CleanName(ATree.Tokens[Index].Text), AClassName) then
      Continue;
    if AReferences <> nil then
    begin
      Found := False;
      for Reference in AReferences do
        if Reference.StartPos = ATree.Tokens[Index].StartPos then
          Found := True;
      if not Found then
        Continue;
    end;
    if First < 0 then
      First := Index;
    if QualifierEdit(ATree.Tokens, Index, AOriginUnit, ANewUnit, Edit) then
      AEdits := AEdits + [Edit];
  end;
  if First < 0 then
    Exit(False);
  if AAddUses and not Contains(TUsesClauses.UsedUnits(ATree.Tokens), ANewUnit) then
  begin
    Clauses := TUsesClauses.Clauses(ATree.Tokens);
    Found := False;
    for Clause in Clauses do
      if not Found and (Contains(Clause.Names, AOriginUnit) or Contains(Clause.Names, ShortName)) then
      begin
        Found := True;
        if TUsesClauses.AddUnit(ATree.Tokens, ATree.Tokens[Clause.UsesIndex].Offset, ANewUnit,
          TTextLines.LineBreakOf(AText), Edit) then
          AEdits := AEdits + [Edit];
      end;
    // Nur über die Referenzsuche sicher: dann im Abschnitt der ersten Stelle.
    if not Found and (AReferences <> nil) and TUsesClauses.AddUnit(ATree.Tokens, ATree.Tokens[First].Offset,
      ANewUnit, TTextLines.LineBreakOf(AText), Edit) then
      AEdits := AEdits + [Edit];
  end;
  Result := AEdits <> nil;
end;

end.
