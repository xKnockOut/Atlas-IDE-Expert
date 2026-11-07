unit Atlas.Common.Editing.ForwardDeclarations;

// Forward-Deklarationen im type-Abschnitt (#685):
//   - Ein Typ wird in einer Typdeklaration benutzt (Feld, Parameter, Ergebnis,
//     Property, generisches Argument, class of), ist aber erst weiter unten im
//     selben Gültigkeitsbereich deklariert (Compiler: E2003). Vorfahren, Aliase
//     (TA = TB) und Zeiger (^T, im selben Block erlaubt) zählen nicht, ebenso
//     Klassenreferenzen (TXClass = class of TX) auf eine Klasse im selben
//     type-Block: Die löst dcc wie Zeiger erst am Blockende auf (#1328).
//     Ebenso ein Name, der weiter unten nur als Alias des gleichnamigen Typs
//     einer anderen Unit steht (TX = UnitY.TX): Bis dahin gilt der Typ aus
//     der uses-Liste, die frühere Verwendung übersetzt.
//   - Korrektur je nach Lage:
//       Klasse/Interface im selben type-Block   Forward-Deklaration am Blockanfang
//       Forward-Deklaration steht weiter unten   sie nach oben verschieben
//       Klasse/Interface in einem späteren Block Blöcke zusammenlegen: const-,
//                                                var- und label-Abschnitte
//                                                dazwischen wandern vor den
//                                                ersten Block, die übrigen
//                                                verlieren ihr "type"; dazu
//                                                die Forward-Deklaration
//       Record und alle anderen Typen            Deklaration vor den ersten
//                                                Verwender verschieben
//     Geht das nicht ohne neue Lücke, bleibt es beim Treffer mit Begründung.
//   - Forward-Deklarationen, deren Typ vor der vollständigen Deklaration nicht
//     benutzt wird, sind überflüssig ("Entfernen").
// Deklarationen in {$IF…}-Blöcken werden übergangen, weil der Syntaxbaum auch
// inaktive Zweige enthält. Alle Edits einer Korrektur bilden einen Schritt.

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree;

type
  TForwardIssue = (UsedBeforeDeclaration, UnneededForward);

  TForwardFix = (NoFix, AddForward, MoveForward, MergeBlocks, MoveDeclaration, RemoveForward);

  TForwardFinding = record
    Issue: TForwardIssue;
    /// <summary>Name des zu früh benutzten bzw. vorwärts deklarierten Typs.</summary>
    TypeName: string;
    /// <summary>Typ, in dem die Verwendung steht; '' bei UnneededForward.</summary>
    UserName: string;
    /// <summary>Verwendung bzw. Forward-Deklaration.</summary>
    Range: TTextRange;
    Fix: TForwardFix;
    Edits: TArray<TTextEdit>;
    /// <summary>Warum es keine Korrektur gibt; '' mit Korrektur.</summary>
    Reason: string;
  end;

  TForwardDeclarations = class
  public
    /// <summary>Alle Treffer der Datei in Textreihenfolge.</summary>
    class function Analyze(ATree: TSyntaxTree; const AText: string): TArray<TForwardFinding>; static;
    /// <summary>Titel der Code-Aktion zu AFix; '' für NoFix.</summary>
    class function FixTitle(AFix: TForwardFix): string; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Defaults,
  System.Generics.Collections,
  Atlas.Common.Pascal.Contract,
  Atlas.Text.Lines,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TForwardDeclarationsText = (TheSectionBetweenTheType, TheSectionBetweenTheType2, BetweenTheTypeBlocksThere,
    TheFirstTypeBlockDoes, NeedsWhichIsDeclaredBefore, DoesNotStartAtThe, SharesLinesWithOtherCode,
    TheForwardDeclarationIsIn, TheForwardDeclarationSharesThe, AddForwardDeclaration, MoveForwardDeclarationUp,
    MergeTypeBlocks, MoveDeclarationUp, RemoveForwardDeclaration);

const
  cTexts: array[TForwardDeclarationsText] of TAtlasText = (
    (De: 'der %s-Abschnitt zwischen den type-Blöcken braucht %s';
     En: 'the %s section between the type blocks needs %s'),
    (De: 'der %s-Abschnitt zwischen den type-Blöcken teilt sich Zeilen mit anderem Code';
     En: 'the %s section between the type blocks shares lines with other code'),
    (De: 'zwischen den type-Blöcken steht mehr als const, var oder label';
     En: 'between the type blocks there is more than const, var or label'),
    (De: 'der erste type-Block beginnt nicht am Zeilenanfang';
     En: 'the first type block does not start at the beginning of the line'),
    (De: '%s braucht %s, das davor deklariert ist'; En: '%s needs %s, which is declared before it'),
    (De: '%s beginnt nicht am Zeilenanfang'; En: '%s does not start at the beginning of the line'),
    (De: '%s teilt sich Zeilen mit anderem Code'; En: '%s shares lines with other code'),
    (De: 'die Forward-Deklaration steht in einem späteren type-Block';
     En: 'the forward declaration is in a later type block'),
    (De: 'die Forward-Deklaration teilt sich die Zeile mit anderem Code';
     En: 'the forward declaration shares the line with other code'),
    (De: 'Forward-Deklaration ergänzen'; En: 'Add forward declaration'),
    (De: 'Forward-Deklaration nach oben verschieben'; En: 'Move forward declaration up'),
    (De: 'type-Blöcke zusammenlegen'; En: 'Merge type blocks'),
    (De: 'Deklaration nach oben verschieben'; En: 'Move declaration up'),
    (De: 'Forward-Deklaration entfernen'; En: 'Remove forward declaration'));

{$SCOPEDENUMS OFF}

type
  TDecl = record
    Node: TSyntaxNode;
    Section: TSyntaxNode;
    Forward: Boolean;
  end;

  TAnalyzer = class
  private
    FTree: TSyntaxTree;
    FText: string;
    FLines: TArray<string>;
    FTable: TLineTable;
    FBreak: string;
    FConditional: TArray<Boolean>;
    FAll: TArray<TDecl>;
    FFindings: TArray<TForwardFinding>;
    procedure MarkLines(AFrom, ATo: Integer);
    procedure MarkConditional;
    function IsConditional(ANode: TSyntaxNode): Boolean;
    function Source(AStart, AEnd: Integer): string;
    function LineText(ALine: Integer): string;
    function LineCount: Integer;
    function WholeLines(AFirst, ALast: TSyntaxNode; out ARange: TTextRange): Boolean;
    function LinesText(const ARange: TTextRange): string;
    function SectionStart(ASection: TSyntaxNode; const AText: string): TTextEdit;
    function ForwardText(const ADecl: TDecl): string;
    function DropKeyword(ASection: TSyntaxNode; out AEdit: TTextEdit): Boolean;
    function BlockStart(const ADecl: TDecl): TSyntaxNode;
    function CollectDecls(AParent: TSyntaxNode): TArray<TDecl>;
    function IsSkippedRef(ADecl, ARef: TSyntaxNode): Boolean;
    function DeclaredBefore(const AName: string; AOffset: Integer): Boolean;
    procedure CheckRefs(const ADecls: TArray<TDecl>; AIndex: Integer);
    procedure Scope(AParent: TSyntaxNode);
    procedure UsedBefore(const AUser, ATarget: TDecl; ARef: TSyntaxNode);
    function TargetRange(const AUser, ATarget: TDecl; ATargetStart: TSyntaxNode; out ARange: TTextRange): Boolean;
    procedure FixMove(var AFinding: TForwardFinding; const AUser, ATarget: TDecl);
    function TakeMoved(const AMoved: TArray<TSyntaxNode>; var AFinding: TForwardFinding; out AText: string): Boolean;
    procedure DropLaterKeywords(const ABlocks: TArray<TSyntaxNode>; var AFinding: TForwardFinding);
    procedure FixMerge(var AFinding: TForwardFinding; const AUser, ATarget: TDecl);
    function RemovalRange(ANode: TSyntaxNode): TTextRange;
    procedure Unneeded(const ADecls: TArray<TDecl>; AIndex: Integer);
  public
    constructor Create(ATree: TSyntaxTree; const AText: string);
    procedure Run;
    property Findings: TArray<TForwardFinding> read FFindings;
  end;

function TypeNode(ADecl: TSyntaxNode): TSyntaxNode;
var
  mIndex: Integer;
begin
  for mIndex := 0 to ADecl.ChildCount - 1 do
  begin
    if ADecl[mIndex].Kind <> TSyntaxKind.GenericParams then
    begin
      Exit(ADecl[mIndex]);
    end;
  end;
  Result := nil;
end;

function IsForwardDecl(ADecl: TSyntaxNode): Boolean;
var
  mNode: TSyntaxNode;
begin
  mNode := TypeNode(ADecl);
  Result := (mNode <> nil) and (mNode.Kind = TSyntaxKind.ForwardType);
end;

/// <summary>Klasse oder Interface: lässt sich vorwärts deklarieren.</summary>
function CanForward(ADecl: TSyntaxNode): Boolean;
var
  mNode: TSyntaxNode;
begin
  mNode := TypeNode(ADecl);
  Result := (mNode <> nil) and ((mNode.Kind = TSyntaxKind.ClassType) or (mNode.Kind = TSyntaxKind.InterfaceType));
end;

function RangeOf(ANode: TSyntaxNode): TTextRange;
begin
  Result := TTextRange.Create(ANode.StartPos, ANode.EndPos);
end;

function Pos_(ALine, ACharacter: Integer): TTextPosition;
begin
  Result := TTextPosition.Create(ALine, ACharacter);
end;

function IsBlank(const AText: string): Boolean;
begin
  Result := Trim(AText) = '';
end;

/// <summary>Zählt ein Typverweis unter AParent? Nicht der Typ selbst (Alias), Zeiger und Vorfahren.</summary>
function IsCountedParent(AParent, ADecl: TSyntaxNode): Boolean;
begin
  Result := (AParent <> ADecl) and not (AParent.Kind in [TSyntaxKind.PointerType, TSyntaxKind.ClassType,
    TSyntaxKind.InterfaceType, TSyntaxKind.ObjectType, TSyntaxKind.HelperType]);
end;

/// <summary>Verwendungen von Typnamen in ADecl: TypeReference ohne Vorfahren, Aliase und Zeiger.</summary>
function RefsOf(ADecl: TSyntaxNode): TArray<TSyntaxNode>;
var
  mRefs: TList<TSyntaxNode>;
  mDecl: TSyntaxNode;
begin
  // Walk statt Rekursion: Konstantenausdrücke im Typ dürfen den Aufrufstapel nicht erschöpfen.
  mDecl := ADecl;
  mRefs := TList<TSyntaxNode>.Create;
  try
    ADecl.Walk(
      function(ANode: TSyntaxNode): Boolean
      begin
        Result := True;
        if (ANode.Kind = TSyntaxKind.TypeReference) and IsCountedParent(ANode.Parent, mDecl) and
          (Pos('.', ANode.Name) = 0) then
        begin
          mRefs.Add(ANode);
        end;
      end);
    Result := mRefs.ToArray;
  finally
    mRefs.Free;
  end;
end;

/// <summary>Bezeichner und Typverweise in ARoot; ihre Namen vergleicht der Aufrufer nach dem ersten Teil
/// vor dem Punkt.</summary>
function NamesIn(ARoot: TSyntaxNode): TArray<TSyntaxNode>;
var
  mNames: TList<TSyntaxNode>;
begin
  mNames := TList<TSyntaxNode>.Create;
  try
    ARoot.Walk(
      function(ANode: TSyntaxNode): Boolean
      begin
        Result := True;
        if (ANode.Kind = TSyntaxKind.Identifier) or (ANode.Kind = TSyntaxKind.TypeReference) then
        begin
          mNames.Add(ANode);
        end;
      end);
    Result := mNames.ToArray;
  finally
    mNames.Free;
  end;
end;

/// <summary>TX = UnitY.TX: Alias des gleichnamigen Typs einer anderen Unit. Diese Unit steht in uses, ihr TX ist
/// also schon vor dem Alias sichtbar.</summary>
function IsSameNameAlias(ADecl: TSyntaxNode): Boolean;
var
  mNode: TSyntaxNode;
  mDot: Integer;
begin
  mNode := TypeNode(ADecl);
  Result := False;
  if (mNode = nil) or (mNode.Kind <> TSyntaxKind.TypeReference) or (mNode.ChildCount > 0) then
  begin
    Exit;
  end;
  mDot := LastDelimiter('.', mNode.Name);
  Result := (mDot > 0) and SameText(Copy(mNode.Name, mDot + 1, MaxInt), ADecl.Name);
end;

/// <summary>True, wenn ARef das Ziel einer Klassenreferenz ist (class of ARef).</summary>
function IsClassReference(ARef: TSyntaxNode): Boolean;
begin
  Result := (ARef.Parent <> nil) and (ARef.Parent.Kind = TSyntaxKind.ClassOfType);
end;

function FirstPart(const AName: string): string;
var
  mDot: Integer;
begin
  mDot := Pos('.', AName);
  if mDot > 0 then
  begin
    Result := Copy(AName, 1, mDot - 1);
  end
  else
  begin
    Result := AName;
  end;
end;

function IsGenericParam(ADecl: TSyntaxNode; const AName: string): Boolean;
var
  mParams: TSyntaxNode;
  mIndex: Integer;
begin
  mParams := ADecl.FindChild(TSyntaxKind.GenericParams);
  if mParams <> nil then
  begin
    for mIndex := 0 to mParams.ChildCount - 1 do
    begin
      if SameText(mParams[mIndex].Name, AName) then
      begin
        Exit(True);
      end;
    end;
  end;
  Result := False;
end;

/// <summary>Deklarationen (const, var, type) eines Abschnitts.</summary>
function DeclaredNodes(ASection: TSyntaxNode): TArray<TSyntaxNode>;
var
  mIndex: Integer;
begin
  Result := nil;
  for mIndex := 0 to ASection.ChildCount - 1 do
  begin
    if ASection[mIndex].Kind in [TSyntaxKind.ConstDecl, TSyntaxKind.VarDecl, TSyntaxKind.TypeDecl] then
    begin
      Result := Result + [ASection[mIndex]];
    end;
  end;
end;

/// <summary>Namen einer Deklaration; var A, B: Integer hat zwei.</summary>
function NamesOf(ADecl: TSyntaxNode): TArray<string>;
var
  mName: string;
begin
  Result := nil;
  for mName in ADecl.Name.Split([',']) do
  begin
    Result := Result + [Trim(mName)];
  end;
end;

/// <summary>Deklarierte Namen eines const-, var- oder type-Abschnitts.</summary>
function DeclaredNames(ASection: TSyntaxNode): TArray<string>;
var
  mNode: TSyntaxNode;
begin
  Result := nil;
  for mNode in DeclaredNodes(ASection) do
  begin
    Result := Result + NamesOf(mNode);
  end;
end;

function SectionWord(ASection: TSyntaxNode): string;
begin
  case ASection.Kind of
    TSyntaxKind.ConstSection:
      Result := 'const';
    TSyntaxKind.VarSection:
      Result := 'var';
    TSyntaxKind.LabelSection:
      Result := 'label';
    TSyntaxKind.TypeSection:
      Result := 'type';
  else
    Result := '';
  end;
end;

function DeclOf(ASection, ANode: TSyntaxNode): TDecl;
begin
  Result.Node := ANode;
  Result.Section := ASection;
  Result.Forward := IsForwardDecl(ANode);
end;

function IsIfStart(const AText: string): Boolean;
begin
  Result := StartsStr('{$IF', AText) or StartsStr('(*$IF', AText);
end;

function IsIfEnd(const AText: string): Boolean;
begin
  Result := StartsStr('{$ENDIF', AText) or StartsStr('{$IFEND', AText) or StartsStr('(*$ENDIF', AText) or
    StartsStr('(*$IFEND', AText);
end;

/// <summary>Index von AChild unter AParent; -1 ohne.</summary>
function IndexIn(AParent, AChild: TSyntaxNode): Integer;
var
  mIndex: Integer;
begin
  Result := -1;
  for mIndex := 0 to AParent.ChildCount - 1 do
  begin
    if AParent[mIndex] = AChild then
    begin
      Result := mIndex;
    end;
  end;
end;

/// <summary>Abschnitte hinter AFirst bis ALast: type-Blöcke und const/var/label; False bei anderem.</summary>
function SplitBetween(AParent: TSyntaxNode; AFirst, ALast: Integer; var ABlocks, AMoved: TArray<TSyntaxNode>): Boolean;
var
  mIndex: Integer;
  mChild: TSyntaxNode;
begin
  for mIndex := AFirst + 1 to ALast do
  begin
    mChild := AParent[mIndex];
    if mChild.Kind = TSyntaxKind.TypeSection then
    begin
      ABlocks := ABlocks + [mChild];
    end
    else if mChild.Kind in [TSyntaxKind.ConstSection, TSyntaxKind.VarSection, TSyntaxKind.LabelSection] then
    begin
      AMoved := AMoved + [mChild];
    end
    else
    begin
      Exit(False);
    end;
  end;
  Result := True;
end;

/// <summary>Erster Name aus ANames, den ARoot benutzt (erster Teil vor dem Punkt); '' ohne.</summary>
function NeededIn(ARoot: TSyntaxNode; const ANames: TArray<string>): string;
var
  mNode: TSyntaxNode;
begin
  for mNode in NamesIn(ARoot) do
  begin
    if MatchText(FirstPart(mNode.Name), ANames) then
    begin
      Exit(FirstPart(mNode.Name));
    end;
  end;
  Result := '';
end;

/// <summary>Braucht ein Abschnitt zwischen den type-Blöcken einen ihrer Typen? Dann der Grund, sonst ''.</summary>
function MovedNeedError(const AMoved, ABlocks: TArray<TSyntaxNode>): string;
var
  mTypeNames: TArray<string>;
  mChild: TSyntaxNode;
  mNeeded: string;
begin
  mTypeNames := nil;
  for mChild in ABlocks do
  begin
    mTypeNames := mTypeNames + DeclaredNames(mChild);
  end;
  for mChild in AMoved do
  begin
    mNeeded := NeededIn(mChild, mTypeNames);
    if mNeeded <> '' then
    begin
      Exit(cTexts[TForwardDeclarationsText.TheSectionBetweenTheType].Fmt([SectionWord(mChild), mNeeded]));
    end;
  end;
  Result := '';
end;

/// <summary>Namen aus ASection, deren Deklaration in AFrom..ATo-1 beginnt.</summary>
function NamesBetween(ASection: TSyntaxNode; AFrom, ATo: Integer): TArray<string>;
var
  mNode: TSyntaxNode;
begin
  Result := nil;
  for mNode in DeclaredNodes(ASection) do
  begin
    if (mNode.StartOffset >= AFrom) and (mNode.StartOffset < ATo) then
    begin
      Result := Result + NamesOf(mNode);
    end;
  end;
end;

/// <summary>In type-, const- und var-Abschnitten von AParent zwischen AFrom und ATo deklarierte Namen.</summary>
function DeclaredBetween(AParent: TSyntaxNode; AFrom, ATo: Integer): TArray<string>;
var
  mIndex: Integer;
begin
  Result := nil;
  for mIndex := 0 to AParent.ChildCount - 1 do
  begin
    if AParent[mIndex].Kind in [TSyntaxKind.TypeSection, TSyntaxKind.ConstSection, TSyntaxKind.VarSection] then
    begin
      Result := Result + NamesBetween(AParent[mIndex], AFrom, ATo);
    end;
  end;
end;

/// <summary>Erster Name aus ABetween, den ATarget außer sich selbst und seinen Typparametern braucht; '' ohne.
/// </summary>
function NeededName(ATarget: TSyntaxNode; const ABetween: TArray<string>): string;
var
  mNode: TSyntaxNode;
begin
  for mNode in NamesIn(ATarget) do
  begin
    if not SameText(mNode.Name, ATarget.Name) and not IsGenericParam(ATarget, mNode.Name) and
      MatchText(FirstPart(mNode.Name), ABetween) then
    begin
      Exit(FirstPart(mNode.Name));
    end;
  end;
  Result := '';
end;

/// <summary>Benutzt ANode den Typ AName (ohne Klassenreferenz)?</summary>
function RefersTo(ANode: TSyntaxNode; const AName: string): Boolean;
var
  mRef: TSyntaxNode;
begin
  for mRef in RefsOf(ANode) do
  begin
    // Eine Klassenreferenz im selben Block braucht die Forward-Deklaration nicht.
    if SameText(mRef.Name, AName) and not IsClassReference(mRef) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Vollständige Deklaration zur Forward-Deklaration ADecls[AIndex] im selben Block; -1 ohne.</summary>
function FullIndex(const ADecls: TArray<TDecl>; AIndex: Integer): Integer;
var
  mIndex: Integer;
begin
  for mIndex := AIndex + 1 to High(ADecls) do
  begin
    if (ADecls[mIndex].Section = ADecls[AIndex].Section) and not ADecls[mIndex].Forward and
      SameText(ADecls[mIndex].Node.Name, ADecls[AIndex].Node.Name) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

/// <summary>Benutzt eine Deklaration des Blocks vor AFull den vorwärts deklarierten Typ?</summary>
function UsedBeforeFull(const ADecls: TArray<TDecl>; AIndex, AFull: Integer): Boolean;
var
  mIndex: Integer;
begin
  for mIndex := 0 to AFull - 1 do
  begin
    if (mIndex <> AIndex) and (ADecls[mIndex].Section = ADecls[AIndex].Section) and
      RefersTo(ADecls[mIndex].Node, ADecls[AIndex].Node.Name) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Erste Deklaration AName hinter AOffset; -1 ohne.</summary>
function TargetIndex(const ADecls: TArray<TDecl>; const AName: string; AOffset: Integer): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(ADecls) do
  begin
    if SameText(ADecls[mIndex].Node.Name, AName) and (ADecls[mIndex].Node.StartOffset > AOffset) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

procedure CollectTypes(ASection: TSyntaxNode; var AAll: TArray<TDecl>);
var
  mChild: Integer;
begin
  for mChild := 0 to ASection.ChildCount - 1 do
  begin
    if ASection[mChild].Kind = TSyntaxKind.TypeDecl then
    begin
      AAll := AAll + [DeclOf(ASection, ASection[mChild])];
    end;
  end;
end;

/// <summary>Legt die Kinder von ANode auf den Stapel und sammelt ihre Typen; True mit type-Abschnitt.</summary>
function PushChildren(ANode: TSyntaxNode; APending: TStack<TSyntaxNode>; var AAll: TArray<TDecl>): Boolean;
var
  mIndex: Integer;
begin
  Result := False;
  for mIndex := 0 to ANode.ChildCount - 1 do
  begin
    if ANode[mIndex].Kind = TSyntaxKind.TypeSection then
    begin
      Result := True;
      CollectTypes(ANode[mIndex], AAll);
    end;
    APending.Push(ANode[mIndex]);
  end;
end;

function CompareFindings(const ALeft, ARight: TForwardFinding): Integer;
begin
  Result := ALeft.Range.StartPos.Line - ARight.Range.StartPos.Line;
  if Result = 0 then
  begin
    Result := ALeft.Range.StartPos.Character - ARight.Range.StartPos.Character;
  end;
end;

/// <summary>Sortiert in Textreihenfolge.</summary>
procedure SortFindings(var AFindings: TArray<TForwardFinding>);
begin
  TArray.Sort<TForwardFinding>(AFindings, TComparer<TForwardFinding>.Construct(
    function(const ALeft, ARight: TForwardFinding): Integer
    begin
      Result := CompareFindings(ALeft, ARight);
    end));
end;

{ TAnalyzer }

constructor TAnalyzer.Create(ATree: TSyntaxTree; const AText: string);
begin
  inherited Create;
  FTree := ATree;
  FText := AText;
  FLines := TTextLines.SplitLines(AText, FBreak);
  FTable := TLineTable.Build(AText);
end;

procedure TAnalyzer.MarkLines(AFrom, ATo: Integer);
var
  mLine: Integer;
begin
  for mLine := AFrom to ATo do
  begin
    if mLine <= High(FConditional) then
    begin
      FConditional[mLine] := True;
    end;
  end;
end;

procedure TAnalyzer.MarkConditional;
var
  mToken: TPascalToken;
  mText: string;
  mDepth, mStartLine: Integer;
begin
  SetLength(FConditional, Length(FLines) + 1);
  mDepth := 0;
  mStartLine := 0;
  for mToken in FTree.Tokens do
  begin
    if mToken.Kind <> TPascalTokenKind.Directive then
    begin
      Continue;
    end;
    mText := UpperCase(mToken.Text);
    if IsIfStart(mText) then
    begin
      if mDepth = 0 then
      begin
        mStartLine := mToken.StartPos.Line;
      end;
      Inc(mDepth);
    end
    else if (mDepth > 0) and IsIfEnd(mText) then
    begin
      Dec(mDepth);
      if mDepth = 0 then
      begin
        MarkLines(mStartLine, mToken.EndPos.Line);
      end;
    end;
  end;
  if mDepth > 0 then
  begin
    MarkLines(mStartLine, High(FConditional));
  end;
end;

function TAnalyzer.IsConditional(ANode: TSyntaxNode): Boolean;
var
  mLine: Integer;
begin
  // Nur die erste Zeile: eine Klasse mit {$IFDEF} im Rumpf bleibt dabei.
  mLine := ANode.StartPos.Line;
  Result := (mLine >= 0) and (mLine <= High(FConditional)) and FConditional[mLine];
end;

function TAnalyzer.Source(AStart, AEnd: Integer): string;
begin
  Result := Copy(FText, AStart + 1, AEnd - AStart);
end;

function TAnalyzer.LineText(ALine: Integer): string;
begin
  if (ALine >= 0) and (ALine <= High(FLines)) then
  begin
    Result := FLines[ALine];
  end
  else
  begin
    Result := '';
  end;
end;

function TAnalyzer.LineCount: Integer;
begin
  Result := Length(FLines);
end;

function TAnalyzer.WholeLines(AFirst, ALast: TSyntaxNode; out ARange: TTextRange): Boolean;
var
  mFirst, mLast: string;
begin
  // Nur ganze Zeilen verschieben: davor und dahinter darf nichts stehen.
  mFirst := LineText(AFirst.StartPos.Line);
  mLast := LineText(ALast.EndPos.Line);
  Result := IsBlank(Copy(mFirst, 1, AFirst.StartPos.Character)) and
    IsBlank(Copy(mLast, ALast.EndPos.Character + 1, MaxInt));
  if not Result then
  begin
    Exit;
  end;
  if ALast.EndPos.Line < LineCount - 1 then
  begin
    ARange := TTextRange.Create(Pos_(AFirst.StartPos.Line, 0), Pos_(ALast.EndPos.Line + 1, 0));
  end
  else
  begin
    ARange := TTextRange.Create(Pos_(AFirst.StartPos.Line, 0), Pos_(ALast.EndPos.Line, Length(mLast)));
  end;
end;

function TAnalyzer.LinesText(const ARange: TTextRange): string;
begin
  Result := Source(FTable.OffsetAt(ARange.StartPos), FTable.OffsetAt(ARange.EndPos));
  if (Result <> '') and not EndsStr(#10, Result) and not EndsStr(#13, Result) then
  begin
    Result := Result + FBreak;
  end;
end;

function TAnalyzer.SectionStart(ASection: TSyntaxNode; const AText: string): TTextEdit;
var
  mFirst: TSyntaxNode;
  mAt: TTextPosition;
begin
  mFirst := ASection[0];
  if mFirst.StartPos.Line > ASection.StartPos.Line then
  begin
    mAt := Pos_(mFirst.StartPos.Line, 0);
    Result := TTextEdit.Create(TTextRange.Create(mAt, mAt),
      TTextLines.IndentOf(LineText(mFirst.StartPos.Line)) + AText + FBreak);
  end
  else
  begin
    Result := TTextEdit.Create(TTextRange.Create(mFirst.StartPos, mFirst.StartPos), AText + ' ');
  end;
end;

function TAnalyzer.ForwardText(const ADecl: TDecl): string;
var
  mNode, mParams: TSyntaxNode;
  mWord: string;
begin
  mNode := TypeNode(ADecl.Node);
  if mNode.Kind = TSyntaxKind.ClassType then
  begin
    mWord := 'class';
  end
  else
  begin
    // interface oder dispinterface: das Schlüsselwort steht am Anfang des Typs.
    mWord := LowerCase(Source(mNode.StartOffset, mNode.StartOffset + Length('dispinterface')));
    if not StartsStr('dispinterface', mWord) then
    begin
      mWord := 'interface';
    end
    else
    begin
      mWord := 'dispinterface';
    end;
  end;
  Result := ADecl.Node.Name;
  mParams := ADecl.Node.FindChild(TSyntaxKind.GenericParams);
  if mParams <> nil then
  begin
    Result := Result + Source(mParams.StartOffset, mParams.EndOffset);
  end;
  Result := Result + ' = ' + mWord + ';';
end;

function TAnalyzer.DropKeyword(ASection: TSyntaxNode; out AEdit: TTextEdit): Boolean;
var
  mLine: string;
  mRange: TTextRange;
begin
  // "type" allein in der Zeile: die Zeile entfällt; sonst bis zur ersten Deklaration.
  mLine := LineText(ASection.StartPos.Line);
  Result := ASection.ChildCount > 0;
  if not Result then
  begin
    Exit;
  end;
  if SameText(Trim(mLine), 'type') then
  begin
    mRange := TTextRange.Create(Pos_(ASection.StartPos.Line, 0), Pos_(ASection.StartPos.Line + 1, 0));
  end
  else if ASection[0].StartPos.Line = ASection.StartPos.Line then
  begin
    mRange := TTextRange.Create(ASection.StartPos, ASection[0].StartPos);
  end
  else
  begin
    mRange := TTextRange.Create(ASection.StartPos, Pos_(ASection.StartPos.Line, ASection.StartPos.Character + 4));
  end;
  AEdit := TTextEdit.Create(mRange, '');
end;

function TAnalyzer.BlockStart(const ADecl: TDecl): TSyntaxNode;
var
  mIndex: Integer;
begin
  // Attribute direkt vor der Deklaration gehören dazu.
  Result := ADecl.Node;
  mIndex := ADecl.Section.ChildCount - 1;
  while (mIndex >= 0) and (ADecl.Section[mIndex] <> ADecl.Node) do
  begin
    Dec(mIndex);
  end;
  while (mIndex > 0) and (ADecl.Section[mIndex - 1].Kind = TSyntaxKind.Attribute) do
  begin
    Dec(mIndex);
    Result := ADecl.Section[mIndex];
  end;
end;

function TAnalyzer.TakeMoved(const AMoved: TArray<TSyntaxNode>; var AFinding: TForwardFinding;
  out AText: string): Boolean;
var
  mChild: TSyntaxNode;
  mRange: TTextRange;
begin
  AText := '';
  for mChild in AMoved do
  begin
    if not WholeLines(mChild, mChild, mRange) then
    begin
      AFinding.Reason := cTexts[TForwardDeclarationsText.TheSectionBetweenTheType2].Fmt([SectionWord(mChild)]);
      Exit(False);
    end;
    AText := AText + LinesText(mRange);
    AFinding.Edits := AFinding.Edits + [TTextEdit.Create(mRange, '')];
  end;
  Result := True;
end;

procedure TAnalyzer.DropLaterKeywords(const ABlocks: TArray<TSyntaxNode>; var AFinding: TForwardFinding);
var
  mLater: Integer;
  mEdit: TTextEdit;
begin
  for mLater := 1 to High(ABlocks) do
  begin
    if DropKeyword(ABlocks[mLater], mEdit) then
    begin
      AFinding.Edits := AFinding.Edits + [mEdit];
    end;
  end;
end;

procedure TAnalyzer.FixMerge(var AFinding: TForwardFinding; const AUser, ATarget: TDecl);
var
  mParent: TSyntaxNode;
  mMoved, mBlocks: TArray<TSyntaxNode>;
  mText: string;
  mAt: TTextPosition;
begin
  mParent := AUser.Section.Parent;
  mMoved := nil;
  mBlocks := TArray<TSyntaxNode>.Create(AUser.Section);
  // Was die Typen aus den Abschnitten dazwischen brauchen, steht danach weiter vorn und bleibt
  // erreichbar. Brauchen umgekehrt die Abschnitte dazwischen einen der Typen, geht es nicht.
  if not SplitBetween(mParent, IndexIn(mParent, AUser.Section), IndexIn(mParent, ATarget.Section), mBlocks,
    mMoved) then
  begin
    AFinding.Reason := cTexts[TForwardDeclarationsText.BetweenTheTypeBlocksThere].Text;
  end
  else
  begin
    AFinding.Reason := MovedNeedError(mMoved, mBlocks);
  end;
  if (AFinding.Reason = '') and
    not IsBlank(Copy(LineText(AUser.Section.StartPos.Line), 1, AUser.Section.StartPos.Character)) then
  begin
    AFinding.Reason := cTexts[TForwardDeclarationsText.TheFirstTypeBlockDoes].Text;
  end;
  if (AFinding.Reason <> '') or not TakeMoved(mMoved, AFinding, mText) then
  begin
    Exit;
  end;
  DropLaterKeywords(mBlocks, AFinding);
  if mText <> '' then
  begin
    mAt := Pos_(AUser.Section.StartPos.Line, 0);
    AFinding.Edits := AFinding.Edits + [TTextEdit.Create(TTextRange.Create(mAt, mAt), mText)];
  end;
  AFinding.Edits := AFinding.Edits + [SectionStart(AUser.Section, ForwardText(ATarget))];
  AFinding.Fix := TForwardFix.MergeBlocks;
end;

function TAnalyzer.TargetRange(const AUser, ATarget: TDecl; ATargetStart: TSyntaxNode;
  out ARange: TTextRange): Boolean;
begin
  // Besteht der Block nur aus dem Typ, entfällt er ganz.
  if (ATarget.Section <> AUser.Section) and (ATarget.Section[0] = ATargetStart) and
    (ATarget.Section[ATarget.Section.ChildCount - 1] = ATarget.Node) and
    WholeLines(ATarget.Section, ATarget.Section, ARange) then
  begin
    Exit(True);
  end;
  Result := WholeLines(ATargetStart, ATarget.Node, ARange);
end;

procedure TAnalyzer.FixMove(var AFinding: TForwardFinding; const AUser, ATarget: TDecl);
var
  mUserStart, mTargetStart: TSyntaxNode;
  mRange: TTextRange;
  mNeeded, mText: string;
  mAt: TTextPosition;
begin
  mUserStart := BlockStart(AUser);
  mTargetStart := BlockStart(ATarget);
  // Was zwischen Verwender und Typ deklariert ist, stünde danach hinter dem Typ: neue Lücke.
  mNeeded := NeededName(ATarget.Node, DeclaredBetween(AUser.Section.Parent, mUserStart.StartOffset,
    mTargetStart.StartOffset));
  if mNeeded <> '' then
  begin
    AFinding.Reason := cTexts[TForwardDeclarationsText.NeedsWhichIsDeclaredBefore].Fmt([ATarget.Node.Name, mNeeded]);
  end
  else if not IsBlank(Copy(LineText(mUserStart.StartPos.Line), 1, mUserStart.StartPos.Character)) then
  begin
    AFinding.Reason := cTexts[TForwardDeclarationsText.DoesNotStartAtThe].Fmt([AUser.Node.Name]);
  end
  else if not TargetRange(AUser, ATarget, mTargetStart, mRange) then
  begin
    AFinding.Reason := cTexts[TForwardDeclarationsText.SharesLinesWithOtherCode].Fmt([ATarget.Node.Name]);
  end;
  if AFinding.Reason <> '' then
  begin
    Exit;
  end;
  mText := TTextLines.IndentOf(LineText(mUserStart.StartPos.Line)) +
    Source(mTargetStart.StartOffset, ATarget.Node.EndOffset) + FBreak;
  mAt := Pos_(mUserStart.StartPos.Line, 0);
  AFinding.Edits := [TTextEdit.Create(TTextRange.Create(mAt, mAt), mText), TTextEdit.Create(mRange, '')];
  AFinding.Fix := TForwardFix.MoveDeclaration;
end;

procedure TAnalyzer.UsedBefore(const AUser, ATarget: TDecl; ARef: TSyntaxNode);
var
  mFinding: TForwardFinding;
  mRange: TTextRange;
begin
  mFinding := Default(TForwardFinding);
  mFinding.Issue := TForwardIssue.UsedBeforeDeclaration;
  mFinding.TypeName := ATarget.Node.Name;
  mFinding.UserName := AUser.Node.Name;
  mFinding.Range := RangeOf(ARef);
  if ATarget.Forward then
  begin
    // Die Forward-Deklaration gibt es schon, nur zu weit unten.
    if ATarget.Section <> AUser.Section then
    begin
      mFinding.Reason := cTexts[TForwardDeclarationsText.TheForwardDeclarationIsIn].Text;
    end
    else if not WholeLines(ATarget.Node, ATarget.Node, mRange) then
    begin
      mFinding.Reason := cTexts[TForwardDeclarationsText.TheForwardDeclarationSharesThe].Text;
    end
    else
    begin
      mFinding.Edits := [TTextEdit.Create(mRange, ''),
        SectionStart(AUser.Section, Source(ATarget.Node.StartOffset, ATarget.Node.EndOffset))];
      mFinding.Fix := TForwardFix.MoveForward;
    end;
  end
  else if CanForward(ATarget.Node) then
  begin
    if ATarget.Section = AUser.Section then
    begin
      mFinding.Edits := [SectionStart(AUser.Section, ForwardText(ATarget))];
      mFinding.Fix := TForwardFix.AddForward;
    end
    else
    begin
      FixMerge(mFinding, AUser, ATarget);
    end;
  end
  else
  begin
    FixMove(mFinding, AUser, ATarget);
  end;
  if mFinding.Fix = TForwardFix.NoFix then
  begin
    mFinding.Edits := nil;
  end;
  FFindings := FFindings + [mFinding];
end;

function TAnalyzer.RemovalRange(ANode: TSyntaxNode): TTextRange;
var
  mLine: string;
  mStop: Integer;
begin
  if WholeLines(ANode, ANode, Result) then
  begin
    Exit;
  end;
  // Mit anderen Deklarationen in der Zeile: nur sie samt folgenden Leerzeichen.
  mLine := LineText(ANode.EndPos.Line);
  mStop := ANode.EndPos.Character;
  while (mStop < Length(mLine)) and CharInSet(mLine[mStop + 1], [' ', #9]) do
  begin
    Inc(mStop);
  end;
  Result := TTextRange.Create(ANode.StartPos, Pos_(ANode.EndPos.Line, mStop));
end;

procedure TAnalyzer.Unneeded(const ADecls: TArray<TDecl>; AIndex: Integer);
var
  mFull: Integer;
  mFinding: TForwardFinding;
begin
  mFull := FullIndex(ADecls, AIndex);
  // Ohne vollständige Deklaration im Block meldet der Compiler selbst (E2086). Benutzt vor der vollständigen
  // Deklaration, auch schon vor der Forward-Deklaration (dann steht sie zu weit unten, das meldet
  // type-used-before-declaration): gebraucht.
  if (mFull < 0) or UsedBeforeFull(ADecls, AIndex, mFull) then
  begin
    Exit;
  end;
  mFinding := Default(TForwardFinding);
  mFinding.Issue := TForwardIssue.UnneededForward;
  mFinding.TypeName := ADecls[AIndex].Node.Name;
  mFinding.Range := RangeOf(ADecls[AIndex].Node);
  mFinding.Edits := [TTextEdit.Create(RemovalRange(ADecls[AIndex].Node), '')];
  mFinding.Fix := TForwardFix.RemoveForward;
  FFindings := FFindings + [mFinding];
end;

function TAnalyzer.CollectDecls(AParent: TSyntaxNode): TArray<TDecl>;
var
  mIndex, mChild: Integer;
  mSection: TSyntaxNode;
begin
  Result := nil;
  for mIndex := 0 to AParent.ChildCount - 1 do
  begin
    mSection := AParent[mIndex];
    if mSection.Kind <> TSyntaxKind.TypeSection then
    begin
      Continue;
    end;
    for mChild := 0 to mSection.ChildCount - 1 do
    begin
      if (mSection[mChild].Kind = TSyntaxKind.TypeDecl) and not IsConditional(mSection[mChild]) then
      begin
        Result := Result + [DeclOf(mSection, mSection[mChild])];
      end;
    end;
  end;
end;

function TAnalyzer.IsSkippedRef(ADecl, ARef: TSyntaxNode): Boolean;
begin
  Result := (ARef.Name = '') or SameText(ARef.Name, ADecl.Name) or IsGenericParam(ADecl, ARef.Name) or
    IsConditional(ARef);
end;

/// <summary>Irgendwo vor AOffset deklariert (auch im interface für das implementation)?</summary>
function TAnalyzer.DeclaredBefore(const AName: string; AOffset: Integer): Boolean;
var
  mDecl: TDecl;
begin
  for mDecl in FAll do
  begin
    if SameText(mDecl.Node.Name, AName) and (mDecl.Node.StartOffset < AOffset) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

procedure TAnalyzer.CheckRefs(const ADecls: TArray<TDecl>; AIndex: Integer);
var
  mRef: TSyntaxNode;
  mTarget: Integer;
begin
  for mRef in RefsOf(ADecls[AIndex].Node) do
  begin
    if IsSkippedRef(ADecls[AIndex].Node, mRef) or DeclaredBefore(mRef.Name, mRef.StartOffset) then
    begin
      Continue;
    end;
    mTarget := TargetIndex(ADecls, mRef.Name, mRef.StartOffset);
    // class of auf eine Klasse weiter unten im selben type-Block übersetzt dcc (#1328); vor TX = UnitY.TX gilt
    // UnitY.TX.
    if (mTarget >= 0) and not (IsClassReference(mRef) and (ADecls[mTarget].Section = ADecls[AIndex].Section)) and
      not IsSameNameAlias(ADecls[mTarget].Node) then
    begin
      UsedBefore(ADecls[AIndex], ADecls[mTarget], mRef);
    end;
  end;
end;

procedure TAnalyzer.Scope(AParent: TSyntaxNode);
var
  mDecls: TArray<TDecl>;
  mIndex: Integer;
begin
  mDecls := CollectDecls(AParent);
  for mIndex := 0 to High(mDecls) do
  begin
    if not mDecls[mIndex].Forward then
    begin
      CheckRefs(mDecls, mIndex);
    end;
  end;
  for mIndex := 0 to High(mDecls) do
  begin
    if mDecls[mIndex].Forward then
    begin
      Unneeded(mDecls, mIndex);
    end;
  end;
end;

procedure TAnalyzer.Run;
var
  mScopes: TList<TSyntaxNode>;
  mPending: TStack<TSyntaxNode>;
  mNode: TSyntaxNode;
begin
  MarkConditional;
  mScopes := TList<TSyntaxNode>.Create;
  mPending := TStack<TSyntaxNode>.Create;
  try
    mPending.Push(FTree.Root);
    while mPending.Count > 0 do
    begin
      mNode := mPending.Pop;
      if PushChildren(mNode, mPending, FAll) then
      begin
        mScopes.Add(mNode);
      end;
    end;
    for mNode in mScopes do
    begin
      Scope(mNode);
    end;
  finally
    mPending.Free;
    mScopes.Free;
  end;
  SortFindings(FFindings);
end;

{ TForwardDeclarations }

class function TForwardDeclarations.Analyze(ATree: TSyntaxTree; const AText: string): TArray<TForwardFinding>;
var
  mAnalyzer: TAnalyzer;
begin
  Result := nil;
  if (ATree = nil) or (ATree.Root = nil) then
  begin
    Exit;
  end;
  mAnalyzer := TAnalyzer.Create(ATree, AText);
  try
    mAnalyzer.Run;
    Result := mAnalyzer.Findings;
  finally
    mAnalyzer.Free;
  end;
end;

class function TForwardDeclarations.FixTitle(AFix: TForwardFix): string;
begin
  case AFix of
    TForwardFix.AddForward:
      Result := cTexts[TForwardDeclarationsText.AddForwardDeclaration].Text;
    TForwardFix.MoveForward:
      Result := cTexts[TForwardDeclarationsText.MoveForwardDeclarationUp].Text;
    TForwardFix.MergeBlocks:
      Result := cTexts[TForwardDeclarationsText.MergeTypeBlocks].Text;
    TForwardFix.MoveDeclaration:
      Result := cTexts[TForwardDeclarationsText.MoveDeclarationUp].Text;
    TForwardFix.RemoveForward:
      Result := cTexts[TForwardDeclarationsText.RemoveForwardDeclaration].Text;
  else
    Result := '';
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Editing.ForwardDeclarations', cTexts);

end.
