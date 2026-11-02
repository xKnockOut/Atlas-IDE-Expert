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
  begin
    Result := Result.Substring(1);
  end;
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
  begin
    if (AOffset >= Item.Start) and (AOffset < Item.Stop) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Typknoten einer Typdeklaration (ohne GenericParams); nil ohne.</summary>
function TypeNodeOf(ADecl: TSyntaxNode): TSyntaxNode;
var
  Index: Integer;
begin
  for Index := 0 to ADecl.ChildCount - 1 do
  begin
    if ADecl[Index].Kind <> TSyntaxKind.GenericParams then
    begin
      Exit(ADecl[Index]);
    end;
  end;
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
  begin
    Result := Result.Substring(2);
  end
  else if Result.StartsWith('(*$') then
  begin
    Result := Result.Substring(3);
  end
  else
  begin
    Result := '';
  end;
end;

/// <summary>+1 öffnet, -1 schließt, 2 verzweigt ({$ELSE}); 0 sonst.</summary>
function ConditionalStep(const AToken: TPascalToken): Integer;
var
  Text: string;
begin
  Result := 0;
  if AToken.Kind <> TPascalTokenKind.Directive then
  begin
    Exit;
  end;
  Text := UpperDirective(AToken);
  if StartsText('IFDEF', Text) or StartsText('IFNDEF', Text) or StartsText('IFOPT', Text) or
    StartsText('IF ', Text) or StartsText('IF(', Text) then
  begin
    Result := 1;
  end
  else if StartsText('ENDIF', Text) or StartsText('IFEND', Text) then
  begin
    Result := -1;
  end
  else if StartsText('ELSE', Text) then
  begin
    Result := 2;
  end;
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
    begin
      Break;
    end;
    Inside := ATokens[Index].Offset >= ARange.Start;
    if Inside and (Depth > 0) then
    begin
      Exit(False);
    end;
    Step := ConditionalStep(ATokens[Index]);
    if Step = 1 then
    begin
      Inc(Depth);
    end
    else if Step = -1 then
    begin
      Dec(Depth);
      if Inside and (Depth < 0) then
      begin
        Exit(False);
      end;
      if Depth < 0 then
      begin
        Depth := 0;
      end;
    end
    else if (Step = 2) and Inside and (Depth = 0) then
    begin
      Exit(False);
    end;
    if Inside and (Depth < 0) then
    begin
      Exit(False);
    end;
  end;
  Result := Depth = 0;
end;

/// <summary>Ist der Text zwischen AFrom und ATo nur Leerraum?</summary>
function Blank(const AText: string; AFrom, ATo: Integer): Boolean;
var
  Index: Integer;
begin
  for Index := AFrom + 1 to ATo do
  begin
    if not CharInSet(AText[Index], [' ', #9, #13, #10]) then
    begin
      Exit(False);
    end;
  end;
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
  begin
    Exit;
  end;
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
  begin
    Exit;
  end;
  Result.Start := ALines.LineStart(First);
  Result.Stop := ALines.LineStart(Last + 1);
  if (Last + 1 < ALines.LineCount) and BlankLine(AText, ALines, First - 1) and BlankLine(AText, ALines, Last + 1) then
  begin
    Result.Stop := ALines.LineStart(Last + 2);
  end;
end;

/// <summary>Text eines Stücks ab Zeilenanfang (Einrückung bleibt), wenn davor nur Leerraum steht.</summary>
function PieceText(const AText: string; const ALines: TLineTable; const APiece: TOffsetRange): string;
var
  Start: Integer;
begin
  Start := ALines.LineStart(ALines.PositionAt(APiece.Start).Line);
  if not Blank(AText, Start, APiece.Start) then
  begin
    Start := APiece.Start;
  end;
  Result := Copy(AText, Start + 1, APiece.Stop - Start);
end;

procedure AddUnique(var AList: TArray<string>; const AName: string);
var
  Item: string;
begin
  for Item in AList do
  begin
    if SameText(Item, AName) then
    begin
      Exit;
    end;
  end;
  AList := AList + [AName];
end;

function Contains(const AList: TArray<string>; const AName: string): Boolean;
var
  Item: string;
begin
  for Item in AList do
  begin
    if SameText(Item, AName) then
    begin
      Exit(True);
    end;
  end;
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
          begin
            Continue;
          end;
          for Name in Child.Name.Split([',']) do
          begin
            if not ANames.ContainsKey(LowerCase(Trim(Name))) then
            begin
              ANames.Add(LowerCase(Trim(Name)), Child.StartOffset);
            end;
          end;
          if Child.Kind = TSyntaxKind.TypeDecl then
          begin
            TypeNode := TypeNodeOf(Child);
            if (TypeNode <> nil) and (TypeNode.Kind = TSyntaxKind.EnumType) then
            begin
              for Item := 0 to TypeNode.ChildCount - 1 do
              begin
                if (TypeNode[Item].Kind = TSyntaxKind.Identifier) and
                  not ANames.ContainsKey(LowerCase(TypeNode[Item].Name)) then
                begin
                  ANames.Add(LowerCase(TypeNode[Item].Name), TypeNode[Item].StartOffset);
                end;
              end;
            end;
          end;
        end;
      TSyntaxKind.RoutineDecl:
        if (Pos('.', Node.Name) = 0) and not ANames.ContainsKey(LowerCase(Node.Name)) then
        begin
          ANames.Add(LowerCase(Node.Name), Node.StartOffset);
        end;
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
          begin
            if (Trim(Name) <> '') and (Pos('.', Name) = 0) then
            begin
              Names.AddOrSetValue(LowerCase(Trim(Name)), True);
            end;
          end;
        TSyntaxKind.GenericParams:
          for Index := 0 to AChild.ChildCount - 1 do
          begin
            Names.AddOrSetValue(LowerCase(AChild[Index].Name), True);
          end;
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
            begin
              Need.Names := [CleanName(AChild.Name)];
            end;
          TSyntaxKind.TypeReference:
            if AChild.Name <> '' then
            begin
              Need.Names := AChild.Name.Split(['.']);
            end;
        else
          // Übrige Werte bewusst ohne Wirkung.
        end;
        if Need.Names <> nil then
        begin
          Needs.Add(Need);
        end;
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
  begin
    Exit;
  end;
  for Index := 0 to ASection.ChildCount - 1 do
  begin
    if ASection[Index].Kind = TSyntaxKind.UsesClause then
    begin
      for Item := 0 to ASection[Index].ChildCount - 1 do
      begin
        AddUnique(Result, ASection[Index][Item].Name);
      end;
    end;
  end;
end;

/// <summary>Schreibweise aus den uses der Ursprungs-Unit (SysUtils statt System.SysUtils), sonst AUnit.</summary>
function Spelling(const AOriginUses: TArray<string>; const AUnit: string): string;
var
  Item: string;
begin
  for Item in AOriginUses do
  begin
    if SameText(Item, AUnit) or EndsText('.' + Item, AUnit) then
    begin
      Exit(Item);
    end;
  end;
  Result := AUnit;
end;

/// <summary>Reihenfolge wie in den uses der Ursprungs-Unit, fremde Units dahinter.</summary>
function Ordered(const AOriginUses, AUnits: TArray<string>): TArray<string>;
var
  Item: string;
begin
  Result := nil;
  for Item in AOriginUses do
  begin
    if Contains(AUnits, Item) then
    begin
      Result := Result + [Item];
    end;
  end;
  for Item in AUnits do
  begin
    AddUnique(Result, Item);
  end;
end;

function UsesText(const AUnits: TArray<string>; const ALineBreak: string): string;
begin
  Result := '';
  if AUnits = nil then
  begin
    Exit;
  end;
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
  begin
    Exit;
  end;
  Name := Dot;
  for Part := High(Parts) downto 0 do
  begin
    if Part < High(Parts) then
    begin
      Name := TRoutineBody.PreviousToken(ATokens, Name);
      if (Name < 0) or not ATokens[Name].IsSymbol('.') then
      begin
        Exit;
      end;
    end;
    Name := TRoutineBody.PreviousToken(ATokens, Name);
    if (Name < 0) or (ATokens[Name].Kind <> TPascalTokenKind.Identifier) or
      not SameText(CleanName(ATokens[Name].Text), Parts[Part]) then
    begin
      Exit;
    end;
  end;
  // Steht davor ein weiterer Punkt, ist es ein Mitglied eines anderen Namens.
  Before := TRoutineBody.PreviousToken(ATokens, Name);
  if (Before >= 0) and ATokens[Before].IsSymbol('.') then
  begin
    Exit;
  end;
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
  begin
    Exit;
  end;
  for Section := 0 to ATree.Root.ChildCount - 1 do
  begin
    Node := ATree.Root[Section];
    if not IsSection(Node) then
    begin
      Continue;
    end;
    for Index := 0 to Node.ChildCount - 1 do
    begin
      if Node[Index].Kind = TSyntaxKind.TypeSection then
      begin
        for Item := 0 to Node[Index].ChildCount - 1 do
        begin
          Decl := Node[Index][Item];
          if (Decl.Kind <> TSyntaxKind.TypeDecl) or (Decl.StartPos.Line <> APosition.Line) then
          begin
            Continue;
          end;
          TypeNode := TypeNodeOf(Decl);
          if (TypeNode <> nil) and (TypeNode.Kind in [TSyntaxKind.ClassType, TSyntaxKind.RecordType]) then
          begin
            Exit(Decl);
          end;
        end;
      end;
    end;
  end;
end;

class function TMoveClass.DefaultUnitName(const AClassName: string): string;
begin
  Result := AClassName;
  if (Length(Result) > 1) and CharInSet(Result[1], ['T', 't']) and CharInSet(Result[2], ['A'..'Z']) then
  begin
    Result := Result.Substring(1);
  end;
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
  begin
    Exit(Fail('keine Klasse an dieser Stelle', AReason));
  end;
  TypeNode := TypeNodeOf(Decl);
  TypeSection := Decl.Parent;
  Section := TypeSection.Parent;
  APlan.ClassName := CleanName(Decl.Name);
  APlan.OriginUnit := ATree.Root.Name;
  APlan.NewUnit := Trim(ANewUnit);
  if not IsValidIdent(APlan.NewUnit, True) then
  begin
    Exit(Fail(Format('„%s“ ist kein gültiger Unit-Name', [APlan.NewUnit]), AReason));
  end;
  if SameText(APlan.NewUnit, APlan.OriginUnit) then
  begin
    Exit(Fail('die neue Unit hieße wie die Ursprungs-Unit', AReason));
  end;
  InterfaceNode := ATree.Root.FindChild(TSyntaxKind.InterfaceSection);
  ImplementationNode := ATree.Root.FindChild(TSyntaxKind.ImplementationSection);
  if (InterfaceNode = nil) or (ImplementationNode = nil) then
  begin
    Exit(Fail('die Unit hat keinen interface- und implementation-Teil', AReason));
  end;
  ImplementationStart := ImplementationNode.StartOffset;
  Lines := TLineTable.Build(AText);
  LineBreak := TTextLines.LineBreakOf(AText);
  // Gleichnamige Typen und Vorwärtsdeklarationen.
  Forwards := nil;
  for Index := 0 to ATree.Root.ChildCount - 1 do
  begin
    Node := ATree.Root[Index];
    if not IsSection(Node) then
    begin
      Continue;
    end;
    for Item := 0 to Node.ChildCount - 1 do
    begin
      if Node[Item].Kind = TSyntaxKind.TypeSection then
      begin
        for Offset := 0 to Node[Item].ChildCount - 1 do
        begin
          if (Node[Item][Offset] <> Decl) and (Node[Item][Offset].Kind = TSyntaxKind.TypeDecl) and
            SameText(CleanName(Node[Item][Offset].Name), APlan.ClassName) then
          begin
            if (TypeNodeOf(Node[Item][Offset]) <> nil) and
              (TypeNodeOf(Node[Item][Offset]).Kind = TSyntaxKind.ForwardType) then
            begin
              Forwards := Forwards + [Node[Item][Offset]];
            end
            else
            begin
              Exit(Fail(Format('mehrere Typen heißen %s', [APlan.ClassName]), AReason));
            end;
          end;
        end;
      end;
    end;
  end;
  // Formularklassen bleiben bei ihrer .dfm bzw. .fmx.
  if (TypeNode.Kind = TSyntaxKind.ClassType) and (TypeNode.ChildCount > 0) and
    (TypeNode[0].Kind = TSyntaxKind.TypeReference) then
  begin
    Ancestor := TypeNode[0].Name;
    if Pos('.', Ancestor) > 0 then
    begin
      Ancestor := Ancestor.Substring(Ancestor.LastIndexOf('.') + 1);
    end;
    if (ContainsText(AText, '{$R *.dfm}') or ContainsText(AText, '{$R *.fmx}') or
      ContainsText(AText, '{$R *.xfm}')) and (MatchText(Ancestor, ['TForm', 'TFrame', 'TDataModule']) or
      EndsText('Form', Ancestor) or EndsText('Frame', Ancestor)) then
    begin
      Exit(Fail('Formularklassen bleiben bei ihrer Formulardatei', AReason));
    end;
  end;
  // Attribute direkt davor gehören zur Deklaration.
  Attributes := nil;
  Index := -1;
  for Item := 0 to TypeSection.ChildCount - 1 do
  begin
    if TypeSection[Item] = Decl then
    begin
      Index := Item;
    end;
  end;
  while (Index > 0) and (TypeSection[Index - 1].Kind = TSyntaxKind.Attribute) do
  begin
    Dec(Index);
    Attributes := [TypeSection[Index]] + Attributes;
  end;
  DeclRange := MakeRange(Decl.StartOffset, Decl.EndOffset);
  if Attributes <> nil then
  begin
    DeclRange.Start := Attributes[0].StartOffset;
  end;
  DeclRange.Start := WithLeadingComments(AText, Lines, ATree.Tokens, DeclRange.Start);
  Methods := nil;
  for Index := 0 to ImplementationNode.ChildCount - 1 do
  begin
    if IsMethodOf(ImplementationNode[Index], APlan.ClassName) then
    begin
      Methods := Methods + [ImplementationNode[Index]];
    end;
  end;
  Moved := [DeclRange];
  for Node in Forwards do
  begin
    Moved := Moved + [MakeRange(WithLeadingComments(AText, Lines, ATree.Tokens, Node.StartOffset), Node.EndOffset)];
  end;
  for Node in Methods do
  begin
    Moved := Moved + [MakeRange(WithLeadingComments(AText, Lines, ATree.Tokens, Node.StartOffset), Node.EndOffset)];
  end;
  for Piece in Moved do
  begin
    if not Unconditional(ATree.Tokens, Piece) then
    begin
      Exit(Fail('ein Teil der Klasse steht in bedingter Übersetzung', AReason));
    end;
  end;
  // Benötigte Namen.
  DeclNeeds := nil;
  CollectNeeds(Decl, DeclNeeds);
  for Node in Attributes do
  begin
    CollectNeeds(Node, DeclNeeds);
  end;
  BodyNeeds := nil;
  for Node in Methods do
  begin
    CollectNeeds(Node, BodyNeeds);
  end;
  TopLevel := TDictionary<string, Integer>.Create;
  Own := TDictionary<string, Boolean>.Create;
  try
    CollectTopLevel(InterfaceNode, TopLevel);
    CollectTopLevel(ImplementationNode, TopLevel);
    CollectOwnNames(Decl, Own);
    for Node in Methods do
    begin
      CollectOwnNames(Node, Own);
    end;
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
      begin
        Needs := DeclNeeds;
      end;
      for Need in Needs do
      begin
        Meaning := Default(TMoveClassMeaning);
        if Assigned(ALookup) then
        begin
          Meaning := ALookup(ATree, AFileName, Need.Names, Need.Node.StartOffset);
        end;
        Name := Need.Names[0];
        // Attribute: [Weak] meint WeakAttribute.
        if not Meaning.Found and Assigned(ALookup) and IsAttributeName(Need.Node) then
        begin
          Meaning := ALookup(ATree, AFileName, [Name + 'Attribute'], Need.Node.StartOffset);
        end;
        if not Meaning.Found then
        begin
          // Ohne Namensauflösung: eigene Namen, dann die der Ursprungs-Unit.
          if (Length(Need.Names) = 1) and (Own.ContainsKey(LowerCase(Name)) or MatchText(Name, SystemNames)) then
          begin
            Continue;
          end;
          if TopLevel.TryGetValue(LowerCase(Name), Offset) then
          begin
            Meaning.Found := True;
            Meaning.UnitName := APlan.OriginUnit;
            Meaning.FileName := AFileName;
            Meaning.Position := Lines.PositionAt(Offset);
          end
          else if SameText(Name, APlan.OriginUnit) then
          begin
            Continue;
          end
          else
          begin
            AddUnique(APlan.Unresolved, string.Join('.', Need.Names));
            if InDecl then
            begin
              UnknownInDecl := True;
            end
            else
            begin
              UnknownInBody := True;
            end;
            Continue;
          end;
        end;
        if Meaning.IsLocal or (Meaning.UnitName = '') or MatchText(Meaning.UnitName, ['System', 'SysInit']) then
        begin
          Continue;
        end;
        if SameText(Meaning.UnitName, APlan.OriginUnit) or
          ((Meaning.FileName <> '') and SameText(Meaning.FileName, AFileName)) then
        begin
          Offset := Lines.OffsetAt(Meaning.Position);
          if InRanges(Moved, Offset) then
          begin
            Continue;
          end;
          if Offset >= ImplementationStart then
          begin
            Exit(Fail(Format('die Klasse verwendet %s aus dem implementation-Teil von %s', [Name,
              APlan.OriginUnit]), AReason));
          end;
          if InDecl then
          begin
            DeclNeedsOrigin := True;
          end
          else
          begin
            BodyNeedsOrigin := True;
          end;
          Continue;
        end;
        if InDecl then
        begin
          AddUnique(DeclUnits, Spelling(OriginUses, Meaning.UnitName));
        end
        else
        begin
          AddUnique(BodyUnits, Spelling(OriginUses, Meaning.UnitName));
        end;
      end;
    end;
  finally
    Own.Free;
    TopLevel.Free;
  end;
  // Verwendet die Ursprungs-Unit die Klasse noch?
  InterfaceRef := False;
  ImplementationRef := False;
  for Index := ATree.FirstTokenFrom(InterfaceNode.StartOffset) to High(ATree.Tokens) do
  begin
    if (ATree.Tokens[Index].Kind = TPascalTokenKind.Identifier) and
      SameText(CleanName(ATree.Tokens[Index].Text), APlan.ClassName) and
      not InRanges(Moved, ATree.Tokens[Index].Offset) and (ATree.Tokens[Index].Offset >= InterfaceNode.StartOffset) then
    begin
      if ATree.Tokens[Index].Offset < ImplementationStart then
      begin
        InterfaceRef := True;
      end
      else
      begin
        ImplementationRef := True;
      end;
    end;
  end;
  if DeclNeedsOrigin and InterfaceRef then
  begin
    Exit(Fail(Format('Kreisverweis: die Klasse braucht Typen aus dem interface von %s, das sie selbst verwendet',
      [APlan.OriginUnit]), AReason));
  end;
  // uses der neuen Unit.
  InterfaceUses := DeclUnits;
  if UnknownInDecl then
  begin
    for Name in SectionUses(InterfaceNode) do
    begin
      AddUnique(InterfaceUses, Name);
    end;
    if Section = ImplementationNode then
    begin
      for Name in SectionUses(ImplementationNode) do
      begin
        AddUnique(InterfaceUses, Name);
      end;
    end;
  end;
  InterfaceUses := Ordered(OriginUses, InterfaceUses);
  if DeclNeedsOrigin then
  begin
    InterfaceUses := InterfaceUses + [APlan.OriginUnit];
  end;
  ImplementationUses := nil;
  for Name in BodyUnits do
  begin
    if not Contains(InterfaceUses, Name) then
    begin
      AddUnique(ImplementationUses, Name);
    end;
  end;
  if UnknownInBody then
  begin
    for Name in OriginUses do
    begin
      if not Contains(InterfaceUses, Name) then
      begin
        AddUnique(ImplementationUses, Name);
      end;
    end;
  end;
  ImplementationUses := Ordered(OriginUses, ImplementationUses);
  if BodyNeedsOrigin and not DeclNeedsOrigin then
  begin
    ImplementationUses := ImplementationUses + [APlan.OriginUnit];
  end;
  APlan.UsesOrigin := DeclNeedsOrigin or BodyNeedsOrigin;
  // Die neue Unit.
  MethodsText := '';
  for Node in Methods do
  begin
    Body := PieceText(AText, Lines, MakeRange(WithLeadingComments(AText, Lines, ATree.Tokens, Node.StartOffset),
      Node.EndOffset));
    if MethodsText <> '' then
    begin
      MethodsText := MethodsText + LineBreak + LineBreak;
    end;
    MethodsText := MethodsText + Body;
  end;
  if MethodsText <> '' then
  begin
    MethodsText := MethodsText + LineBreak + LineBreak;
  end;
  APlan.Text := 'unit ' + APlan.NewUnit + ';' + LineBreak + LineBreak + 'interface' + LineBreak + LineBreak +
    UsesText(InterfaceUses, LineBreak) + 'type' + LineBreak + PieceText(AText, Lines, DeclRange) + LineBreak +
    LineBreak + 'implementation' + LineBreak + LineBreak + UsesText(ImplementationUses, LineBreak) + MethodsText +
    'end.' + LineBreak;
  // Entfernen; ein Typabschnitt, der leer würde, entfällt ganz.
  WholeSection := True;
  for Index := 0 to TypeSection.ChildCount - 1 do
  begin
    if not InRanges(Moved, TypeSection[Index].StartOffset) then
    begin
      WholeSection := False;
    end;
  end;
  Removals := nil;
  if WholeSection then
  begin
    Removals := [MakeRange(WithLeadingComments(AText, Lines, ATree.Tokens, TypeSection.StartOffset),
      TypeSection.EndOffset)];
  end;
  for Piece in Moved do
  begin
    if not (WholeSection and (Piece.Start >= TypeSection.StartOffset) and (Piece.Stop <= TypeSection.EndOffset)) then
    begin
      Removals := Removals + [Piece];
    end;
  end;
  for Index := 0 to High(Removals) do
  begin
    Removals[Index] := RemovalRange(AText, Lines, Removals[Index]);
  end;
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
      begin
        Last.Stop := Piece.Stop;
      end;
      Continue;
    end;
    if Last.Start >= 0 then
    begin
      Edits := Edits + [TTextEdit.Create(TTextRange.Create(Lines.PositionAt(Last.Start), Lines.PositionAt(Last.Stop)),
        '')];
    end;
    Last := Piece;
  end;
  if Last.Start >= 0 then
  begin
    Edits := Edits + [TTextEdit.Create(TTextRange.Create(Lines.PositionAt(Last.Start), Lines.PositionAt(Last.Stop)),
      '')];
  end;
  // Die Ursprungs-Unit bindet die neue Unit ein, wo sie die Klasse noch verwendet.
  if InterfaceRef or ImplementationRef then
  begin
    if InterfaceRef then
    begin
      Offset := InterfaceNode.StartOffset;
    end
    else
    begin
      Offset := ImplementationStart;
    end;
    if not TUsesClauses.AddUnit(ATree.Tokens, Offset, APlan.NewUnit, LineBreak, Edit) then
    begin
      Exit(Fail('kein Platz für die neue Unit im uses', AReason));
    end;
    Edits := Edits + [Edit];
  end;
  for Index := 0 to High(ATree.Tokens) do
  begin
    if (ATree.Tokens[Index].Kind = TPascalTokenKind.Identifier) and
      SameText(CleanName(ATree.Tokens[Index].Text), APlan.ClassName) and
      not InRanges(Moved, ATree.Tokens[Index].Offset) and
      QualifierEdit(ATree.Tokens, Index, APlan.OriginUnit, APlan.NewUnit, Edit) then
    begin
      Edits := Edits + [Edit];
    end;
  end;
  APlan.OriginEdits := Edits;
  // Vorher fehlerfrei, nachher auch.
  Before := Length(ATree.Diagnostics);
  if Before = 0 then
  begin
    Applied := TChangeSignature.ApplyEdits(AText, Edits);
    Check := TSyntaxTreeCache.Parse(Applied);
    try
      if Length(Check.Diagnostics) > 0 then
      begin
        Exit(Fail('die Ursprungs-Unit parst danach nicht mehr', AReason));
      end;
    finally
      Check.Free;
    end;
    Check := TSyntaxTreeCache.Parse(APlan.Text);
    try
      if Length(Check.Diagnostics) > 0 then
      begin
        Exit(Fail('die neue Unit parst nicht', AReason));
      end;
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
  begin
    ShortName := ShortName.Substring(ShortName.LastIndexOf('.') + 1);
  end;
  First := -1;
  for Index := 0 to High(ATree.Tokens) do
  begin
    if (ATree.Tokens[Index].Kind <> TPascalTokenKind.Identifier) or
      not SameText(CleanName(ATree.Tokens[Index].Text), AClassName) then
    begin
      Continue;
    end;
    if AReferences <> nil then
    begin
      Found := False;
      for Reference in AReferences do
      begin
        if Reference.StartPos = ATree.Tokens[Index].StartPos then
        begin
          Found := True;
        end;
      end;
      if not Found then
      begin
        Continue;
      end;
    end;
    if First < 0 then
    begin
      First := Index;
    end;
    if QualifierEdit(ATree.Tokens, Index, AOriginUnit, ANewUnit, Edit) then
    begin
      AEdits := AEdits + [Edit];
    end;
  end;
  if First < 0 then
  begin
    Exit(False);
  end;
  if AAddUses and not Contains(TUsesClauses.UsedUnits(ATree.Tokens), ANewUnit) then
  begin
    Clauses := TUsesClauses.Clauses(ATree.Tokens);
    Found := False;
    for Clause in Clauses do
    begin
      if not Found and (Contains(Clause.Names, AOriginUnit) or Contains(Clause.Names, ShortName)) then
      begin
        Found := True;
        if TUsesClauses.AddUnit(ATree.Tokens, ATree.Tokens[Clause.UsesIndex].Offset, ANewUnit,
          TTextLines.LineBreakOf(AText), Edit) then
        begin
          AEdits := AEdits + [Edit];
        end;
      end;
    end;
    // Nur über die Referenzsuche sicher: dann im Abschnitt der ersten Stelle.
    if not Found and (AReferences <> nil) and TUsesClauses.AddUnit(ATree.Tokens, ATree.Tokens[First].Offset,
      ANewUnit, TTextLines.LineBreakOf(AText), Edit) then
    begin
      AEdits := AEdits + [Edit];
    end;
  end;
  Result := AEdits <> nil;
end;

end.
