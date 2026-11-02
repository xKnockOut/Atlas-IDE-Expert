unit Atlas.Common.Editing.ExtractSuperclass;

// „Basisklasse herauslösen“ (#713): Gewählte Felder, Methoden und Properties
// einer Klasse wandern in eine neue Vorfahrklasse, die direkt über der Klasse
// in derselben Unit entsteht (eine neue Unit macht daraus
// Atlas.Common.Lsp.ExtractSuperclass über „Klasse verschieben“).
//
//   - Die neue Klasse erbt vom bisherigen Vorfahren (ohne Interfaces), die
//     Klasse von der neuen; Interfaces bleiben bei der Klasse.
//   - Je Methode „verschieben“ (Deklaration und Rumpf wandern) oder
//     „abstrakt“ (oben virtual; abstract;, unten override, der Rumpf bleibt).
//   - Abhängigkeiten: Ein verschobenes Mitglied darf nur Mitglieder benutzen,
//     die mitwandern (abstrakte Methoden zählen); sonst nennt der Plan sie.
//   - Sichtbarkeit: Ein strict-private-Mitglied, das oben landet und unten
//     weiter benutzt wird, wird protected bzw. strict protected (Einstellung);
//     ein private-Mitglied nur, wenn die Basisklasse in eine andere Unit kommt
//     (in derselben Unit sieht die Klasse es ohnehin) oder Code außerhalb der
//     Klasse es dort benutzt.
//   - Konstruktoren und Destruktoren: Setzen die Anweisungen direkt hinter
//     inherited Felder, die wandern, bekommt die Basisklasse einen
//     Konstruktor mit derselben Signatur und diesen Anweisungen; die Klasse
//     ruft ihn mit inherited auf. Beim Destruktor entsprechend die
//     Anweisungen direkt vor inherited. Wandern nur Anweisungen, die keine
//     lokalen Variablen und keine bleibenden Mitglieder benutzen, damit die
//     Reihenfolge erhalten bleibt.
//
// Gerechnet wird in Schritten (Änderungen anwenden, neu parsen): erst die
// Klasse ändern, dann die gehobenen abstrakten Methoden umsetzen, zuletzt die
// Basisklasse und ihre Rümpfe einfügen. Ergebnis ist der neue Text der Unit.

interface

uses
  System.SysUtils,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Editing.ClassLayout,
  Atlas.Common.Editing.MemberTransfer,
  Atlas.Common.Editing.ExtractInterface;

type
  /// <summary>Ist AName ein Interface (für den ersten Eintrag der Vorfahrenliste)?</summary>
  TIsInterfaceType = reference to function(const AName: string): Boolean;

  TSuperclassInfo = record
    ClassName: string;
    SuggestedName: string;
    /// <summary>Bisheriger Vorfahr (ohne Interfaces); '' ohne.</summary>
    Ancestor: string;
    Candidates: TArray<TTransferCandidate>;
    Notes: TArray<string>;
  end;

  TSuperclassRequest = record
    Name: string;
    /// <summary>Ids der gewählten Mitglieder.</summary>
    Members: TArray<Integer>;
    /// <summary>Ids der Methoden, die oben abstrakt werden (Teilmenge von Members).</summary>
    Abstract: TArray<Integer>;
    /// <summary>Die Basisklasse bleibt in der Unit der Klasse.</summary>
    SameUnit: Boolean;
    /// <summary>Protected_ oder StrictProtected.</summary>
    RaiseVisibility: TClassVisibility;
  end;

  TSuperclassPlan = record
    ClassName: string;
    BaseName: string;
    /// <summary>Neuer Text der Unit samt Basisklasse.</summary>
    Text: string;
    /// <summary>Kopfzeile der Basisklasse in Text.</summary>
    BaseLine: Integer;
    Moved: TArray<string>;
    Abstracts: TArray<string>;
    /// <summary>Gehobene private-Mitglieder.</summary>
    Raised: TArray<string>;
    /// <summary>Aufgeteilte Konstruktoren und Destruktoren.</summary>
    Split: TArray<string>;
    Warnings: TArray<string>;
  end;

  TExtractSuperclass = class
  public const
    Kind = 'refactor.extract';
  public
    /// <summary>Vorgeschlagener Name: ohne T, ohne erstes Wort bei mehreren, mit ASuffix (TPdfExport →
    /// TExportBase); ASuffix Custom wird Präfix (TCustomExport).</summary>
    class function SuggestName(const AClassName, ASuffix: string): string; static;
    /// <summary>Klasse auf der Kopfzeile ALine; nil ohne.</summary>
    class function ClassAt(ATree: TSyntaxTree; ALine: Integer): TSyntaxNode; static;
    /// <summary>Kandidaten und Vorschlag; False mit Grund ohne Klasse oder ohne Kandidaten.</summary>
    class function Prepare(ATree: TSyntaxTree; const AText: string; ALine: Integer; const ASuffix: string;
      const ANameInUse: TNameInUse; out AInfo: TSuperclassInfo; out AReason: string): Boolean; static;
    /// <summary>Neuer Text der Unit für ARequest; False mit Grund (Name, Auswahl, Abhängigkeiten).</summary>
    class function Plan(ATree: TSyntaxTree; const AText: string; ALine: Integer;
      const ARequest: TSuperclassRequest; const AIsInterface: TIsInterfaceType; const ANameInUse: TNameInUse;
      out APlan: TSuperclassPlan; out AReason: string): Boolean; static;
  end;

implementation

uses
  System.StrUtils,
  Atlas.Text.Lines,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Editing.TextChanges;

type
  /// <summary>Aufteilung eines Konstruktors bzw. Destruktors.</summary>
  TStatementSplit = record
    Member: Integer;
    /// <summary>Oberste Anweisungen des Rumpfs, die wandern.</summary>
    Moved: TArray<TSyntaxNode>;
    /// <summary>Die inherited-Anweisung; nil ohne.</summary>
    Inherited_: TSyntaxNode;
    /// <summary>Namen, die die bleibenden Anweisungen benutzen.</summary>
    Remaining: TArray<string>;
  end;

function Fail(const AReason: string; out AOut: string): Boolean;
begin
  AOut := AReason;
  Result := False;
end;

function ContainsText(const AList: TArray<string>; const AValue: string): Boolean;
var
  Item: string;
begin
  for Item in AList do
  begin
    if SameText(Item, AValue) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function StripT(const AName: string): string;
begin
  Result := AName;
  if (Length(Result) > 1) and CharInSet(Result[1], ['T', 't']) and CharInSet(Result[2], ['A'..'Z']) then
  begin
    Result := Copy(Result, 2, MaxInt);
  end;
end;

/// <summary>Wortteile eines Namens in CamelCase (PdfExport → Pdf, Export; HTMLView → HTML, View).</summary>
function Words(const AName: string): TArray<string>;
var
  Index, Start: Integer;
begin
  Result := nil;
  Start := 1;
  for Index := 2 to Length(AName) do
  begin
    if CharInSet(AName[Index], ['A'..'Z']) and (CharInSet(AName[Index - 1], ['a'..'z', '0'..'9']) or
      ((Index < Length(AName)) and CharInSet(AName[Index + 1], ['a'..'z']) and
      CharInSet(AName[Index - 1], ['A'..'Z']))) then
    begin
      Result := Result + [Copy(AName, Start, Index - Start)];
      Start := Index;
    end;
  end;
  if Start <= Length(AName) then
  begin
    Result := Result + [Copy(AName, Start, MaxInt)];
  end;
end;

/// <summary>Namen, die ANode benutzt: Bezeichner und Self.X.</summary>
procedure CollectNames(ANode: TSyntaxNode; var ANames: TArray<string>);
var
  Index: Integer;
begin
  if ANode = nil then
  begin
    Exit;
  end;
  if ANode.Kind = TSyntaxKind.Identifier then
  begin
    ANames := ANames + [ANode.Name];
  end
  else if (ANode.Kind = TSyntaxKind.MemberAccess) and (ANode.ChildCount > 0) and
    (ANode[0].Kind = TSyntaxKind.Identifier) and SameText(ANode[0].Name, 'Self') then
  begin
    ANames := ANames + [ANode.Name];
  end;
  for Index := 0 to ANode.ChildCount - 1 do
  begin
    CollectNames(ANode[Index], ANames);
  end;
end;

function NamesOf(ANode: TSyntaxNode): TArray<string>;
begin
  Result := nil;
  CollectNames(ANode, Result);
end;

function HasInherited(ANode: TSyntaxNode): Boolean;
var
  Index: Integer;
begin
  if ANode.Kind = TSyntaxKind.InheritedExpr then
  begin
    Exit(True);
  end;
  // Nur der Aufruf selbst, nicht Argumente.
  if ANode.Kind in [TSyntaxKind.CallStatement, TSyntaxKind.Call] then
  begin
    for Index := 0 to ANode.ChildCount - 1 do
    begin
      if HasInherited(ANode[Index]) then
      begin
        Exit(True);
      end;
    end;
  end;
  Result := False;
end;

/// <summary>Lokale Variablen und Konstanten einer Routine.</summary>
function LocalNames(ABody: TSyntaxNode): TArray<string>;
var
  Index, Item: Integer;
  Name: string;
begin
  Result := nil;
  for Index := 0 to ABody.ChildCount - 1 do
  begin
    if ABody[Index].Kind in [TSyntaxKind.VarSection, TSyntaxKind.ConstSection] then
    begin
      for Item := 0 to ABody[Index].ChildCount - 1 do
      begin
        for Name in ABody[Index][Item].Name.Split([',']) do
        begin
          if Trim(Name) <> '' then
          begin
            Result := Result + [Trim(Name)];
          end;
        end;
      end;
    end;
  end;
end;

/// <summary>Steht die Anweisung allein auf ihren Zeilen (davor nur Leerraum, dahinter höchstens ";")?</summary>
function WholeLines(ALayout: TClassLayout; ANode: TSyntaxNode): Boolean;
var
  First, Last: string;
begin
  First := ALayout.Lines[ANode.StartPos.Line];
  Last := ALayout.Lines[ANode.EndPos.Line];
  Result := (Trim(Copy(First, 1, ANode.StartPos.Character)) = '') and
    MatchText(Trim(Copy(Last, ANode.EndPos.Character + 1, MaxInt)), ['', ';']);
end;

function BlockOf(ABody: TSyntaxNode): TSyntaxNode;
begin
  Result := nil;
  if ABody <> nil then
  begin
    Result := ABody.FindChild(TSyntaxKind.Block);
  end;
end;

/// <summary>Anweisungen von AMember (Konstruktor oder Destruktor), die in die Basisklasse wandern können.
/// </summary>
function SplitOf(ALayout: TClassLayout; AMember: Integer; const AAllowed, AOwn: TArray<string>;
  out ASplit: TStatementSplit): Boolean;
var
  Member: TClassMember;
  Block: TSyntaxNode;
  Locals, Names: TArray<string>;
  Index, Inherit, Step: Integer;
  Statement: TSyntaxNode;
  Name: string;
  UsesMoved, Blocked: Boolean;
begin
  ASplit := Default(TStatementSplit);
  ASplit.Member := AMember;
  Member := ALayout.Members[AMember];
  Block := BlockOf(Member.Body);
  if Block = nil then
  begin
    Exit(False);
  end;
  // Der Destruktor der Basisklasse läuft nur über override.
  if (Member.Kind = TClassMemberKind.Destructor_) and not Member.HasDirective('override') then
  begin
    Exit(False);
  end;
  Locals := LocalNames(Member.Body);
  Inherit := -1;
  for Index := 0 to Block.ChildCount - 1 do
  begin
    if HasInherited(Block[Index]) then
    begin
      Inherit := Index;
      Break;
    end;
  end;
  if Inherit >= 0 then
  begin
    ASplit.Inherited_ := Block[Inherit];
  end;
  // Konstruktor: zusammenhängend direkt hinter inherited; Destruktor: direkt davor (Reihenfolge bleibt).
  if Member.Kind = TClassMemberKind.Constructor_ then
  begin
    Index := Inherit + 1;
    Step := 1;
  end
  else
  begin
    Index := Inherit - 1;
    if Inherit < 0 then
    begin
      Index := Block.ChildCount - 1;
    end;
    Step := -1;
  end;
  while (Index >= 0) and (Index < Block.ChildCount) do
  begin
    Statement := Block[Index];
    if not WholeLines(ALayout, Statement) then
    begin
      Break;
    end;
    Names := NamesOf(Statement);
    UsesMoved := False;
    Blocked := False;
    for Name in Names do
    begin
      if ContainsText(Locals, Name) then
      begin
        Blocked := True;
      end
      else if ContainsText(AAllowed, Name) then
      begin
        UsesMoved := True;
      end
      else if ContainsText(AOwn, Name) then
      begin
        Blocked := True;
      end;
    end;
    if Blocked or not UsesMoved then
    begin
      Break;
    end;
    if Step > 0 then
    begin
      ASplit.Moved := ASplit.Moved + [Statement];
    end
    else
    begin
      ASplit.Moved := [Statement] + ASplit.Moved;
    end;
    Inc(Index, Step);
  end;
  for Index := 0 to Block.ChildCount - 1 do
  begin
    if not ((ASplit.Moved <> nil) and (Block[Index].StartOffset >= ASplit.Moved[0].StartOffset) and
      (Block[Index].EndOffset <= ASplit.Moved[High(ASplit.Moved)].EndOffset)) then
    begin
      ASplit.Remaining := ASplit.Remaining + NamesOf(Block[Index]);
    end;
  end;
  Result := ASplit.Moved <> nil;
end;

/// <summary>Zeilen AFirst..ALast der Anweisungen samt Umbruch.</summary>
function StatementLines(ALayout: TClassLayout; AFirst, ALast: TSyntaxNode): string;
begin
  Result := ALayout.LinesText(AFirst.StartPos.Line, ALast.EndPos.Line);
end;

/// <summary>Bereich der ganzen Zeilen AFirstLine..ALastLine samt Umbruch.</summary>
function LinesRange(AFirstLine, ALastLine: Integer): TTextRange;
begin
  Result := TTextRange.Create(AFirstLine, 0, ALastLine + 1, 0);
end;

/// <summary>Deklaration eines aufgeteilten Konstruktors bzw. Destruktors für oben (wie unten).</summary>
function SplitDeclaration(ALayout: TClassLayout; AIndex: Integer): string;
var
  Directive: string;
begin
  Result := ALayout.Head(AIndex);
  for Directive in TMemberTransfer.DirectiveTexts(ALayout, ALayout.Members[AIndex].Node) do
  begin
    Result := Result + ' ' + Directive + ';';
  end;
end;

/// <summary>Typparameter ohne Einschränkungen ("&lt;T: class; U&gt;" → "&lt;T, U&gt;"); '' ohne.</summary>
function GenericArgs(const AParams: string): string;
var
  Inner, Part, Name: string;
  Names: TArray<string>;
begin
  if AParams = '' then
  begin
    Exit('');
  end;
  Inner := Copy(AParams, 2, Length(AParams) - 2);
  Names := nil;
  for Part in Inner.Split([',', ';']) do
  begin
    Name := Trim(Part);
    if Pos(':', Name) > 0 then
    begin
      Name := Trim(Copy(Name, 1, Pos(':', Name) - 1));
    end;
    if IsIdentifier(Name) then
    begin
      Names := Names + [Name];
    end;
  end;
  Result := '<' + string.Join(', ', Names) + '>';
end;

/// <summary>Kopf eines Rumpfs mit ABaseName statt des Klassennamens.</summary>
function BodyHeader(ALayout: TClassLayout; AIndex: Integer; const ABaseName: string): string;
var
  Body, Header: TSyntaxNode;
  Text: string;
  Position: Integer;
begin
  Body := ALayout.Members[AIndex].Body;
  Header := Body.FindChild(TSyntaxKind.RoutineHeader);
  Text := Copy(ALayout.Text, Body.StartOffset + 1, Header.EndOffset - Body.StartOffset);
  if not Text.EndsWith(';') then
  begin
    Text := Text + ';';
  end;
  // Der erste Klassenname vor dem Punkt.
  Position := Pos(LowerCase(ALayout.Name) + '.', LowerCase(Text));
  if Position = 0 then
  begin
    Position := Pos(LowerCase(ALayout.Name) + '<', LowerCase(Text));
  end;
  if Position > 0 then
  begin
    Text := Copy(Text, 1, Position - 1) + ABaseName + Copy(Text, Position + Length(ALayout.Name), MaxInt);
  end;
  Result := Text;
end;

/// <summary>Ein aufgeteilter Konstruktor bzw. Destruktor benutzt AName nur noch, wenn die bleibenden Anweisungen
/// es tun.</summary>
function StaysUsed(const ASplits: TArray<TStatementSplit>; const AName: string): TStillUses;
begin
  Result :=
    function(AUser: Integer): Boolean
    var
      Split: TStatementSplit;
    begin
      Result := True;
      for Split in ASplits do
      begin
        if Split.Member = AUser then
        begin
          Result := ContainsText(Split.Remaining, AName);
        end;
      end;
    end;
end;

{ TExtractSuperclass }

class function TExtractSuperclass.SuggestName(const AClassName, ASuffix: string): string;
var
  Parts: TArray<string>;
  Rest: string;
begin
  Rest := StripT(AClassName);
  Parts := Words(Rest);
  if Length(Parts) > 1 then
  begin
    Rest := string.Join('', Copy(Parts, 1, MaxInt));
  end;
  if SameText(ASuffix, 'Custom') then
  begin
    Result := 'TCustom' + Rest;
  end
  else
  begin
    Result := 'T' + Rest + ASuffix;
  end;
end;

class function TExtractSuperclass.ClassAt(ATree: TSyntaxTree; ALine: Integer): TSyntaxNode;
begin
  Result := TClassLayout.DeclAt(ATree, ALine, False);
end;

class function TExtractSuperclass.Prepare(ATree: TSyntaxTree; const AText: string; ALine: Integer;
  const ASuffix: string; const ANameInUse: TNameInUse; out AInfo: TSuperclassInfo; out AReason: string): Boolean;
var
  Decl: TSyntaxNode;
  Layout: TClassLayout;
  Counter: Integer;
  Member: TClassMember;
  Name, Suffix: string;
  HasSplit: Boolean;
begin
  AInfo := Default(TSuperclassInfo);
  AReason := '';
  Decl := ClassAt(ATree, ALine);
  if Decl = nil then
  begin
    Exit(Fail('An dieser Stelle steht keine Klasse.', AReason));
  end;
  Layout := TClassLayout.Read(ATree, AText, Decl);
  try
    AInfo.ClassName := Layout.Name;
    if (Layout.Ancestors <> nil) and not SameText(Layout.Ancestors[0], 'TObject') then
    begin
      AInfo.Ancestor := Layout.Ancestors[0];
    end;
    HasSplit := False;
    for Member in Layout.Members do
    begin
      if Member.Kind in [TClassMemberKind.Constructor_, TClassMemberKind.Destructor_] then
      begin
        HasSplit := True;
      end;
    end;
    AInfo.Candidates := TMemberTransfer.Candidates(Layout);
    if AInfo.Candidates = nil then
    begin
      Exit(Fail(Format('%s hat keine Felder, Methoden oder Properties für eine Basisklasse.', [Layout.Name]),
        AReason));
    end;
    Suffix := ASuffix;
    if Suffix = '' then
    begin
      Suffix := 'Base';
    end;
    Name := SuggestName(Layout.Name, Suffix);
    if Assigned(ANameInUse) and ANameInUse(Name) then
    begin
      // Mit dem ganzen Namen (TPdfExportBase), dann mit Zahl.
      if SameText(Suffix, 'Custom') then
      begin
        Name := 'TCustom' + StripT(Layout.Name);
      end
      else
      begin
        Name := 'T' + StripT(Layout.Name) + Suffix;
      end;
      if ANameInUse(Name) then
      begin
        Counter := 2;
        while ANameInUse(Name + IntToStr(Counter)) and (Counter < 100) do
        begin
          Inc(Counter);
        end;
        Name := Name + IntToStr(Counter);
      end;
    end;
    AInfo.SuggestedName := Name;
    if HasSplit then
    begin
      AInfo.Notes := AInfo.Notes + ['Konstruktoren und Destruktoren bleiben; Anweisungen direkt bei inherited, die ' +
        'nur verschobene Felder setzen bzw. freigeben, wandern in einen eigenen der Basisklasse.'];
    end;
  finally
    Layout.Free;
  end;
  Result := True;
end;

class function TExtractSuperclass.Plan(ATree: TSyntaxTree; const AText: string; ALine: Integer;
  const ARequest: TSuperclassRequest; const AIsInterface: TIsInterfaceType; const ANameInUse: TNameInUse;
  out APlan: TSuperclassPlan; out AReason: string): Boolean;
var
  Layout, Next: TClassLayout;
  Tree: TSyntaxTree;
  Info: TSuperclassInfo;
  Candidate: TTransferCandidate;
  Id, Index, Line, FirstBody: Integer;
  Member: TClassMember;
  Olds: TArray<TClassMember>;
  Moved, Abstracts, Chosen, Relocate: TArray<Integer>;
  Missing, AllowedNames, OwnNames, BaseLines, Bodies, Ancestors: TArray<string>;
  Visibilities: array[TClassVisibility] of TArray<string>;
  FinalVisibility: array of TClassVisibility;
  Splits: TArray<TStatementSplit>;
  Split: TStatementSplit;
  Edits: TArray<TTextEdit>;
  Visibility: TClassVisibility;
  ForwardNeeded: Boolean;
  LineBreak, Indent, Text, Header, Body, Name, Ancestor, BaseText, Statement: string;
  HeaderOffset: Integer;
begin
  APlan := Default(TSuperclassPlan);
  AReason := '';
  if not Prepare(ATree, AText, ALine, 'Base', nil, Info, AReason) then
  begin
    Exit(False);
  end;
  Name := Trim(ARequest.Name);
  if not IsIdentifier(Name) then
  begin
    Exit(Fail(Format('"%s" ist kein gültiger Bezeichner.', [Name]), AReason));
  end;
  if SameText(Name, Info.ClassName) then
  begin
    Exit(Fail('Die Basisklasse darf nicht wie die Klasse heißen.', AReason));
  end;
  if Assigned(ANameInUse) and ANameInUse(Name) then
  begin
    Exit(Fail(Format('Der Name %s ist schon vergeben.', [Name]), AReason));
  end;
  if ARequest.Members = nil then
  begin
    Exit(Fail('Bitte mindestens ein Mitglied wählen.', AReason));
  end;
  Chosen := nil;
  for Id in ARequest.Members do
  begin
    Index := TMemberTransfer.IndexOf(Info.Candidates, Id);
    if Index < 0 then
    begin
      Exit(Fail(Format('Mitglied %d ist kein Kandidat.', [Id]), AReason));
    end;
    if not Info.Candidates[Index].Enabled then
    begin
      Exit(Fail(Format('%s kann nicht wandern: %s.', [Info.Candidates[Index].Name, Info.Candidates[Index].Reason]),
        AReason));
    end;
    if not TMemberTransfer.Has(Chosen, Id) then
    begin
      Chosen := Chosen + [Id];
    end;
  end;
  Moved := nil;
  Abstracts := nil;
  for Candidate in Info.Candidates do
  begin
    if not TMemberTransfer.Has(Chosen, Candidate.Id) then
    begin
      Continue;
    end;
    if TMemberTransfer.Has(ARequest.Abstract, Candidate.Id) then
    begin
      if not Candidate.CanAbstract then
      begin
        Exit(Fail(Format('%s kann nicht abstrakt werden: %s.', [Candidate.Name, Candidate.Reason]), AReason));
      end;
      Abstracts := Abstracts + [Candidate.Id];
    end
    else
    begin
      Moved := Moved + [Candidate.Id];
    end;
  end;
  Layout := TClassLayout.Read(ATree, AText, ClassAt(ATree, ALine));
  try
    // Was wandert, darf nur benutzen, was mitwandert (abstrakt zählt).
    Missing := TMemberTransfer.MissingNeeds(Layout, Moved, Chosen);
    if Missing <> nil then
    begin
      Exit(Fail(string.Join('; ', Missing) + '. Bitte mitnehmen oder abstrakt deklarieren.', AReason));
    end;
    LineBreak := Layout.LineBreak;
    APlan.ClassName := Layout.Name;
    APlan.BaseName := Name;
    // Namen der Mitglieder: was oben steht (auch abstrakt) und was unten bleibt.
    AllowedNames := nil;
    OwnNames := nil;
    for Index := 0 to High(Layout.Members) do
    begin
      if TMemberTransfer.Has(Chosen, Index) then
      begin
        AllowedNames := AllowedNames + [Layout.Members[Index].Name];
      end
      else if Layout.Members[Index].Kind <> TClassMemberKind.Other then
      begin
        OwnNames := OwnNames + [Layout.Members[Index].Name];
      end;
    end;
    // Konstruktoren und Destruktoren aufteilen.
    Splits := nil;
    for Index := 0 to High(Layout.Members) do
    begin
      if (Layout.Members[Index].Kind in [TClassMemberKind.Constructor_, TClassMemberKind.Destructor_]) and
        not Layout.Members[Index].IsClassMember and SplitOf(Layout, Index, AllowedNames, OwnNames, Split) then
      begin
        Splits := Splits + [Split];
      end;
    end;
    // Sichtbarkeit oben.
    FinalVisibility := nil;
    SetLength(FinalVisibility, Length(Layout.Members));
    for Index := 0 to High(Layout.Members) do
    begin
      FinalVisibility[Index] := Layout.Members[Index].Visibility;
    end;
    Relocate := nil;
    for Id in Chosen do
    begin
      Member := Layout.Members[Id];
      if not TMemberTransfer.MustRaise(Layout, Id, Moved, TMemberTransfer.Has(Abstracts, Id), ARequest.SameUnit,
        StaysUsed(Splits, Member.Name)) then
      begin
        Continue;
      end;
      FinalVisibility[Id] := ARequest.RaiseVisibility;
      APlan.Raised := APlan.Raised + [Member.Name];
      APlan.Warnings := APlan.Warnings + [Format('%s wird %s, weil %s es weiter benutzt.', [Member.Name,
        TClassEdits.VisibilityName(ARequest.RaiseVisibility), Layout.Name])];
      // Die Überschreibung unten braucht dieselbe Sichtbarkeit (sonst H2269).
      if TMemberTransfer.Has(Abstracts, Id) then
      begin
        Relocate := Relocate + [Id];
      end;
    end;
    // Deklarationen oben, je Abschnitt Felder vor Methoden und Properties.
    for Visibility := Low(TClassVisibility) to High(TClassVisibility) do
    begin
      Visibilities[Visibility] := nil;
    end;
    for Index := 0 to High(Layout.Members) do
    begin
      if TMemberTransfer.Has(Moved, Index) and (Layout.Members[Index].Kind in [TClassMemberKind.Field,
        TClassMemberKind.ClassVar]) then
      begin
        Visibilities[FinalVisibility[Index]] := Visibilities[FinalVisibility[Index]] + TMemberTransfer.MemberLines(Layout, Index);
      end;
    end;
    for Split in Splits do
    begin
      Visibilities[Layout.Members[Split.Member].Visibility] := Visibilities[Layout.Members[Split.Member].Visibility] +
        [Layout.MemberIndent + SplitDeclaration(Layout, Split.Member)];
    end;
    for Index := 0 to High(Layout.Members) do
    begin
      if TMemberTransfer.Has(Abstracts, Index) then
      begin
        Visibilities[FinalVisibility[Index]] := Visibilities[FinalVisibility[Index]] +
          [Layout.MemberIndent + TMemberTransfer.AbstractDeclaration(Layout, Index)];
      end
      else if TMemberTransfer.Has(Moved, Index) and not (Layout.Members[Index].Kind in [TClassMemberKind.Field,
        TClassMemberKind.ClassVar]) then
      begin
        Visibilities[FinalVisibility[Index]] := Visibilities[FinalVisibility[Index]] + TMemberTransfer.MemberLines(Layout, Index);
      end;
    end;
    Indent := Layout.Indent;
    Ancestor := '';
    if (Layout.Ancestors <> nil) and not SameText(Layout.Ancestors[0], 'TObject') then
    begin
      Ancestor := Layout.Ancestors[0];
      if Assigned(AIsInterface) and AIsInterface(Ancestor) then
      begin
        Ancestor := '';
      end
      else if not Assigned(AIsInterface) and (Length(Ancestor) > 1) and (Ancestor[1] = 'I') and
        CharInSet(Ancestor[2], ['A'..'Z']) then
      begin
        Ancestor := '';
      end;
    end;
    BaseLines := nil;
    Header := Indent + Name + Layout.GenericParams + ' = class';
    if Ancestor <> '' then
    begin
      Header := Header + '(' + Ancestor + ')';
    end;
    BaseLines := BaseLines + [Header];
    for Visibility := Low(TClassVisibility) to High(TClassVisibility) do
    begin
      if Visibilities[Visibility] <> nil then
      begin
        BaseLines := BaseLines + [Indent + TClassEdits.VisibilityName(Visibility)] + Visibilities[Visibility];
      end;
    end;
    BaseLines := BaseLines + [Indent + 'end;'];
    // In derselben Unit trennt eine Leerzeile die Klassen; für eine neue Unit wandert die Basisklasse gleich
    // weiter, ohne eine Leerzeile zurückzulassen.
    BaseText := string.Join(LineBreak, BaseLines) + LineBreak;
    if ARequest.SameUnit then
    begin
      BaseText := BaseText + LineBreak;
    end;
    // Braucht oben jemand die Klasse selbst, steht vorher eine Vorwärtsdeklaration.
    ForwardNeeded := False;
    HeaderOffset := 0;
    for Text in BaseLines do
    begin
      for Statement in TArray<string>(Text.Split([' ', '(', ')', ':', ';', ',', '<', '>', '[', ']', '.'])) do
      begin
        if SameText(Statement, Layout.Name) then
        begin
          ForwardNeeded := True;
        end;
      end;
    end;
    if ForwardNeeded then
    begin
      ATree.Root.Walk(
        function(ANode: TSyntaxNode): Boolean
        begin
          Result := True;
          if (ANode.Kind = TSyntaxKind.TypeDecl) and SameText(ANode.Name, Layout.Name) and
            (ANode.StartPos.Line < Layout.HeaderLine) then
          begin
            ForwardNeeded := False;
          end;
        end);
      if ForwardNeeded then
      begin
        BaseText := Indent + Layout.Name + Layout.GenericParams + ' = class;' + LineBreak + LineBreak + BaseText;
        HeaderOffset := 2;
      end;
    end;
    // Rümpfe oben.
    Bodies := nil;
    for Split in Splits do
    begin
      Member := Layout.Members[Split.Member];
      Body := BodyHeader(Layout, Split.Member, Name) + LineBreak +
        TTextLines.IndentOf(Layout.Lines[BlockOf(Member.Body).StartPos.Line]) + 'begin' + LineBreak;
      if (Member.Kind = TClassMemberKind.Constructor_) and (Split.Inherited_ <> nil) then
      begin
        Body := Body + StatementLines(Layout, Split.Inherited_, Split.Inherited_);
      end;
      Body := Body + StatementLines(Layout, Split.Moved[0], Split.Moved[High(Split.Moved)]);
      if (Member.Kind = TClassMemberKind.Destructor_) and (Split.Inherited_ <> nil) then
      begin
        Body := Body + StatementLines(Layout, Split.Inherited_, Split.Inherited_);
      end;
      Body := Body + TTextLines.IndentOf(Layout.Lines[BlockOf(Member.Body).StartPos.Line]) + 'end;';
      Bodies := Bodies + [Body];
      APlan.Split := APlan.Split + [Member.Name];
    end;
    for Index := 0 to High(Layout.Members) do
    begin
      if TMemberTransfer.Has(Moved, Index) and (Layout.Members[Index].Body <> nil) then
      begin
        Bodies := Bodies + [TClassEdits.BodyText(Layout, Index, Name)];
      end;
    end;
    for Index := 0 to High(Layout.Members) do
    begin
      if TMemberTransfer.Has(Moved, Index) then
      begin
        APlan.Moved := APlan.Moved + [Layout.Members[Index].Name];
      end
      else if TMemberTransfer.Has(Abstracts, Index) then
      begin
        APlan.Abstracts := APlan.Abstracts + [Layout.Members[Index].Name];
      end;
    end;
    // Schritt 1: Klasse ändern; Abschnitte, deren Mitglieder alle wandern, fallen weg.
    Edits := TClassEdits.DeleteMembers(Layout, Moved, True) + TMemberTransfer.EmptiedSections(Layout, Moved);
    for Id in Abstracts do
    begin
      Edits := Edits + TMemberTransfer.OverrideEdits(Layout, Layout.Members[Id].Node, True);
    end;
    for Split in Splits do
    begin
      Member := Layout.Members[Split.Member];
      // Oben steht er wie bisher; unten überschreibt er ihn (virtual) bzw. verdeckt ihn ohne reintroduce.
      if Member.HasDirective('virtual') or Member.HasDirective('dynamic') or Member.HasDirective('reintroduce') then
      begin
        Edits := Edits + TMemberTransfer.OverrideEdits(Layout, Member.Node, False);
      end;
      Statement := '';
      if (Split.Inherited_ = nil) or (Member.Kind = TClassMemberKind.Destructor_) then
      begin
        // Ohne inherited ruft die Klasse den neuen Konstruktor bzw. Destruktor an der Stelle auf.
        if Split.Inherited_ = nil then
        begin
          Statement := TTextLines.IndentOf(Layout.Lines[Split.Moved[0].StartPos.Line]) + 'inherited;' + LineBreak;
        end;
      end
      else if not SameText(Trim(StatementLines(Layout, Split.Inherited_, Split.Inherited_)), 'inherited;') then
      begin
        Edits := Edits + [TTextEdit.Create(LinesRange(Split.Inherited_.StartPos.Line, Split.Inherited_.EndPos.Line),
          TTextLines.IndentOf(Layout.Lines[Split.Inherited_.StartPos.Line]) + 'inherited;' + LineBreak)];
      end;
      Edits := Edits + [TTextEdit.Create(LinesRange(Split.Moved[0].StartPos.Line,
        Split.Moved[High(Split.Moved)].EndPos.Line), Statement)];
    end;
    Ancestors := [Name + GenericArgs(Layout.GenericParams)];
    for Index := 0 to High(Layout.Ancestors) do
    begin
      if (Index > 0) or (Ancestor = '') and not SameText(Layout.Ancestors[0], 'TObject') then
      begin
        Ancestors := Ancestors + [Layout.Ancestors[Index]];
      end;
    end;
    Edits := Edits + [TClassEdits.SetAncestors(Layout, Ancestors)];
    Text := TTextChanges.Apply(AText, Edits);
    // Schritt 2: gehobene abstrakte Methoden unten in den Abschnitt der neuen Sichtbarkeit.
    Olds := nil;
    for Id in Relocate do
    begin
      Olds := Olds + [Layout.Members[Id]];
    end;
    if not TMemberTransfer.Relocate(Text, Layout.Name, Olds, ARequest.RaiseVisibility) then
    begin
      Exit(Fail('Die Klasse ist nach dem Umbau nicht mehr lesbar.', AReason));
    end;
    // Schritt 3: Basisklasse über die Klasse, ihre Rümpfe vor die der Klasse.
    Next := TMemberTransfer.ParseLayout(Text, Layout.Name, Tree);
    if Next = nil then
    begin
      Exit(Fail('Die Klasse ist nach dem Umbau nicht mehr lesbar.', AReason));
    end;
    try
      Edits := [TClassEdits.InsertBeforeLine(Next.FirstLine, BaseText)];
      APlan.BaseLine := Next.FirstLine + HeaderOffset;
      if Bodies <> nil then
      begin
        FirstBody := -1;
        for Member in Next.Members do
        begin
          if (Member.Body <> nil) and ((FirstBody < 0) or (Member.BodyFirstLine < FirstBody)) then
          begin
            FirstBody := Member.BodyFirstLine;
          end;
        end;
        if FirstBody >= 0 then
        begin
          Edits := Edits + [TClassEdits.InsertBeforeLine(FirstBody, string.Join(LineBreak + LineBreak, Bodies) +
            LineBreak + LineBreak)];
        end
        else
        begin
          Line := TClassEdits.BodiesEnd(Tree, Layout.Name);
          if Line < 0 then
          begin
            Exit(Fail('Die Unit hat keinen implementation-Teil für die Rümpfe der Basisklasse.', AReason));
          end;
          Edits := Edits + [TClassEdits.InsertBodies(Text, Line, Bodies)];
        end;
      end;
      APlan.Text := TTextChanges.Apply(Text, Edits);
    finally
      Next.Free;
      Tree.Free;
    end;
  finally
    Layout.Free;
  end;
  Result := True;
end;

end.
