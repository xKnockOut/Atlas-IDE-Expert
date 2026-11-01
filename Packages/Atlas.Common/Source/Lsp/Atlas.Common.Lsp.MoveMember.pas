unit Atlas.Common.Lsp.MoveMember;

// „Mitglied in Vorfahr oder Nachfahr verschieben“ über das Protokoll (#675):
//   - Code-Aktionen „„Run“ in Vorfahr verschieben …“ (der Vorfahr liegt im
//     Projekt, nicht in RTL/VCL) und „„Run“ in Nachfahren verschieben …“ (es
//     gibt direkte Nachfahren im Projekt) auf einem Feld, einer Methode oder
//     einer Property der Klassendeklaration, nur mit refactoring.moveMember.
//     Sie tragen den Client-Befehl atlas.moveMember mit [uri, position,
//     "up"|"down"].
//   - atlas.server.moveMember.prepare [uri, position, richtung]: Klasse,
//     Mitglied, Kandidaten (das Mitglied an der Stelle angehakt), Ziele
//     (nach oben die Vorfahren des Projekts, der direkte vorgewählt; nach
//     unten die direkten Nachfahren, alle vorgewählt) und die Wahl „andere
//     Nachfahren überschreiben“ bzw. „abstrakte Deklaration im Vorfahr
//     lassen“.
//   - atlas.server.moveMember [uri, position, richtung, {members, abstract,
//     targets, option}]: WorkspaceEdit mit Änderungsanmerkung über alle
//     betroffenen Dateien. Nach unten sucht es vorher die Verweise auf die
//     Mitglieder (#29): Stellen außerhalb der Klasse und der gewählten
//     Nachfahren verbieten das Verschieben. Liegt das Ziel in einer anderen
//     Unit, ergänzt es dort die uses für die benutzten Namen (interface für
//     Deklarationen, implementation für Rümpfe); Kreisverweise und Namen, die
//     nur im implementation-Teil der Quelle stehen, brechen ab.
// Die Logik liegt in Atlas.Common.Editing.MoveMember.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Lsp.References;

type
  TMoveMemberContext = record
    Index: ISymbolIndex;
    ReadText: TReferenceReadText;
    /// <summary>Dateien des Projekts für die Referenzsuche.</summary>
    Files: TArray<string>;
  end;

  TLspMoveMember = class
  public const
    ClientCommand = 'atlas.moveMember';
    PrepareCommand = 'atlas.server.moveMember.prepare';
    ApplyCommand = 'atlas.server.moveMember';
    AnnotationId = 'moveMember';
  public
    /// <summary>Die Code-Aktionen an APosition, wenn eingeschaltet und es dort ein Ziel gibt; sonst nil. Der
    /// Aufrufer übernimmt die Objekte.</summary>
    class function Actions(AEnabled: Boolean; ATree: TSyntaxTree; const AText, AFileName, AUri: string;
      const APosition: TTextPosition; const AIndex: ISymbolIndex): TArray<TJSONObject>; static;
    /// <summary>Antwort auf prepare; EJsonRpcError ohne Mitglied oder Ziel. Der Aufrufer übernimmt das Objekt.
    /// </summary>
    class function Prepare(ATree: TSyntaxTree; const AText, AFileName: string; const APosition: TTextPosition;
      const ADirection: string; const AContext: TMoveMemberContext): TJSONObject; static;
    /// <summary>{"edit": WorkspaceEdit, "warnings": [...], "file": URI des (ersten) Ziels, "line": Kopfzeile der
    /// Zielklasse dort, "moved": Zahl};
    /// EJsonRpcError bei ungültiger Anfrage. Der Aufrufer übernimmt das Objekt.</summary>
    class function Execute(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName, AText: string;
      const APosition: TTextPosition; const ADirection: string; ARequest: TJSONValue;
      const AContext: TMoveMemberContext): TJSONObject; static;
  end;

implementation

uses
  System.Generics.Collections,
  System.StrUtils,
  Atlas.Text.Lines,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Editing.ClassLayout,
  Atlas.Common.Editing.UsesClause,
  Atlas.Common.Editing.TextChanges,
  Atlas.Common.Editing.MemberTransfer,
  Atlas.Common.Editing.MoveMember,
  Atlas.Common.Editing.MoveClass,
  Atlas.Common.Lsp.Contract,
  Atlas.Common.Lsp.Positions,
  Atlas.Common.Lsp.MoveClass,
  Atlas.Common.Lsp.WorkspaceChanges;

type
  /// <summary>Klasse des Projekts mit Unit und Vorfahr.</summary>
  TClassHit = record
    Ref: TMemberClassRef;
    UnitName: string;
    Ancestor: string;
  end;

const
  /// <summary>Höchstens so viele Vorfahren nach oben.</summary>
  MaxDepth = 16;

function Failed(const AMessage: string): EJsonRpcError;
begin
  Result := EJsonRpcError.Create(TLspErrorCode.RequestFailed, 'Mitglied verschieben: ' + AMessage);
end;

function PlainName(const AName: string): string;
begin
  Result := Trim(AName);
  if Pos('<', Result) > 0 then
  begin
    Result := Trim(Copy(Result, 1, Pos('<', Result) - 1));
  end;
end;

function IsUp(const ADirection: string): Boolean;
begin
  if SameText(ADirection, 'up') then
  begin
    Result := True;
  end
  else if SameText(ADirection, 'down') then
  begin
    Result := False;
  end
  else
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, 'Richtung "up" oder "down" fehlt');
  end;
end;

/// <summary>Liegt die Datei in einer Bibliothek (RTL/VCL, Suchpfade)?</summary>
function IsLibrary(const AIndex: ISymbolIndex; const AFileName: string): Boolean;
var
  UnitIndex: TUnitIndex;
begin
  Result := not AIndex.FindFile(AFileName, UnitIndex) or UnitIndex.Library_;
end;

/// <summary>Klasse AName des Projekts: in ATree (Datei AFileName) oder im Index.</summary>
function FindClass(ATree: TSyntaxTree; const AText, AFileName: string; const AIndex: ISymbolIndex;
  const AName: string; out AHit: TClassHit): Boolean;
var
  Decl: TSyntaxNode;
  Layout: TClassLayout;
  Location: TSymbolLocation;
  Name: string;
begin
  AHit := Default(TClassHit);
  Name := PlainName(AName);
  if (Name = '') or SameText(Name, 'TObject') then
  begin
    Exit(False);
  end;
  Decl := TClassLayout.DeclNamed(ATree, Name);
  if Decl <> nil then
  begin
    Layout := TClassLayout.Read(ATree, AText, Decl);
    try
      AHit.Ref := TMemberClassRef.Create(AFileName, Layout.Name);
      AHit.UnitName := TUsesClauses.OwnName(ATree.Tokens);
      if Layout.Ancestors <> nil then
      begin
        AHit.Ancestor := Layout.Ancestors[0];
      end;
    finally
      Layout.Free;
    end;
    Exit(True);
  end;
  if AIndex <> nil then
  begin
    for Location in AIndex.FindSymbols(Name) do
    begin
      if (Location.Symbol.Kind = TIndexSymbolKind.ClassType) and (Location.Symbol.Container = '') and
        not SameText(Location.FileName, AFileName) and not IsLibrary(AIndex, Location.FileName) then
      begin
        AHit.Ref := TMemberClassRef.Create(Location.FileName, Location.Symbol.Name);
        AHit.UnitName := Location.UnitName;
        if Location.Symbol.Ancestors <> nil then
        begin
          AHit.Ancestor := Location.Symbol.Ancestors[0];
        end;
        Exit(True);
      end;
    end;
  end;
  Result := False;
end;

/// <summary>Vorfahren des Projekts ab AAncestor, der direkte zuerst.</summary>
function AncestorChain(ATree: TSyntaxTree; const AText, AFileName: string; const AIndex: ISymbolIndex;
  const AAncestor: string): TArray<TClassHit>;
var
  Hit: TClassHit;
  Name: string;
begin
  Result := nil;
  Name := AAncestor;
  while (Length(Result) < MaxDepth) and FindClass(ATree, AText, AFileName, AIndex, Name, Hit) do
  begin
    Result := Result + [Hit];
    Name := Hit.Ancestor;
  end;
end;

/// <summary>Direkte Nachfahren von AClassName im Projekt: in ATree und im Index.</summary>
function DirectDescendants(ATree: TSyntaxTree; const AText, AFileName: string; const AIndex: ISymbolIndex;
  const AClassName: string): TArray<TClassHit>;
var
  Decl: TSyntaxNode;
  Layout: TClassLayout;
  Location: TSymbolLocation;
  Hit: TClassHit;
begin
  Result := nil;
  for Decl in TClassLayout.AllDecls(ATree) do
  begin
    Layout := TClassLayout.Read(ATree, AText, Decl);
    try
      if (Layout.Ancestors <> nil) and SameText(PlainName(Layout.Ancestors[0]), AClassName) then
      begin
        Hit := Default(TClassHit);
        Hit.Ref := TMemberClassRef.Create(AFileName, Layout.Name);
        Hit.UnitName := TUsesClauses.OwnName(ATree.Tokens);
        Hit.Ancestor := Layout.Ancestors[0];
        Result := Result + [Hit];
      end;
    finally
      Layout.Free;
    end;
  end;
  if AIndex = nil then
  begin
    Exit;
  end;
  for Location in AIndex.Descendants(AClassName) do
  begin
    if (Location.Symbol.Kind = TIndexSymbolKind.ClassType) and not SameText(Location.FileName, AFileName) and
      not IsLibrary(AIndex, Location.FileName) and (Location.Symbol.Ancestors <> nil) and
      SameText(PlainName(Location.Symbol.Ancestors[0]), AClassName) then
    begin
      Hit := Default(TClassHit);
      Hit.Ref := TMemberClassRef.Create(Location.FileName, Location.Symbol.Name);
      Hit.UnitName := Location.UnitName;
      Hit.Ancestor := Location.Symbol.Ancestors[0];
      Result := Result + [Hit];
    end;
  end;
end;

function KindText(AKind: TTransferKind): string;
begin
  case AKind of
    TTransferKind.Field:
      Result := 'field';
    TTransferKind.Property_:
      Result := 'property';
  else
    Result := 'method';
  end;
end;

function Info(ATree: TSyntaxTree; const AText: string; const APosition: TTextPosition): TMoveMemberInfo;
var
  Reason: string;
begin
  if not TMoveMember.Prepare(ATree, AText, APosition.Line, Result, Reason) then
  begin
    raise Failed(Reason);
  end;
end;

function Action(const ATitle, AUri: string; const APosition: TTextPosition; const ADirection: string): TJSONObject;
var
  Arguments: TJSONArray;
  Command: TJSONObject;
begin
  Arguments := TJSONArray.Create;
  Arguments.Add(AUri);
  Arguments.AddElement(TLspPositions.PositionToJson(APosition));
  Arguments.Add(ADirection);
  Command := TJSONObject.Create;
  Command.AddPair('title', ATitle);
  Command.AddPair('command', TLspMoveMember.ClientCommand);
  Command.AddPair('arguments', Arguments);
  Result := TJSONObject.Create;
  Result.AddPair('title', ATitle);
  Result.AddPair('kind', TMoveMember.Kind);
  Result.AddPair('command', Command);
end;

class function TLspMoveMember.Actions(AEnabled: Boolean; ATree: TSyntaxTree; const AText, AFileName,
  AUri: string; const APosition: TTextPosition; const AIndex: ISymbolIndex): TArray<TJSONObject>;
var
  Found: TMoveMemberInfo;
  Reason: string;
  Hit: TClassHit;
begin
  Result := nil;
  if not AEnabled or (ATree = nil) or not TMoveMember.Prepare(ATree, AText, APosition.Line, Found, Reason) then
  begin
    Exit;
  end;
  if FindClass(ATree, AText, AFileName, AIndex, Found.Ancestor, Hit) then
  begin
    Result := Result + [Action(Format('„%s“ in Vorfahr verschieben …', [Found.SelectedName]), AUri, APosition,
      'up')];
  end;
  if DirectDescendants(ATree, AText, AFileName, AIndex, Found.ClassName) <> nil then
  begin
    Result := Result + [Action(Format('„%s“ in Nachfahren verschieben …', [Found.SelectedName]), AUri, APosition,
      'down')];
  end;
end;

class function TLspMoveMember.Prepare(ATree: TSyntaxTree; const AText, AFileName: string;
  const APosition: TTextPosition; const ADirection: string; const AContext: TMoveMemberContext): TJSONObject;
var
  Found: TMoveMemberInfo;
  Up: Boolean;
  Hits: TArray<TClassHit>;
  Hit: TClassHit;
  Item: TTransferCandidate;
  List, Needs, Targets: TJSONArray;
  Entry, Option: TJSONObject;
  Need: Integer;
begin
  Up := IsUp(ADirection);
  Found := Info(ATree, AText, APosition);
  if Up then
  begin
    Hits := AncestorChain(ATree, AText, AFileName, AContext.Index, Found.Ancestor);
  end
  else
  begin
    Hits := DirectDescendants(ATree, AText, AFileName, AContext.Index, Found.ClassName);
  end;
  if (Hits = nil) and Up then
  begin
    raise Failed(Format('%s hat keinen Vorfahren im Projekt.', [Found.ClassName]));
  end;
  if Hits = nil then
  begin
    raise Failed(Format('%s hat keine Nachfahren im Projekt.', [Found.ClassName]));
  end;
  Result := TJSONObject.Create;
  Result.AddPair('className', Found.ClassName);
  Result.AddPair('ownUnit', TUsesClauses.OwnName(ATree.Tokens));
  Result.AddPair('member', Found.SelectedName);
  Result.AddPair('direction', LowerCase(ADirection));
  Result.AddPair('name', '');
  List := TJSONArray.Create;
  for Item in Found.Candidates do
  begin
    Entry := TJSONObject.Create;
    Entry.AddPair('id', TJSONNumber.Create(Item.Id));
    Entry.AddPair('name', Item.Name);
    Entry.AddPair('kind', KindText(Item.Kind));
    Entry.AddPair('display', Item.Display);
    Entry.AddPair('visibility', TClassEdits.VisibilityName(Item.Visibility));
    Entry.AddPair('checked', TJSONBool.Create(Item.Id = Found.Selected));
    Entry.AddPair('enabled', TJSONBool.Create(Item.Enabled));
    Entry.AddPair('reason', Item.Reason);
    // Abstrakt wählen gibt es nur nach oben; nach unten gilt die Wahl für alle Methoden.
    Entry.AddPair('canAbstract', TJSONBool.Create(Up and Item.CanAbstract));
    Entry.AddPair('abstract', TJSONBool.Create(False));
    Needs := TJSONArray.Create;
    for Need in Item.Needs do
    begin
      Needs.AddElement(TJSONNumber.Create(Need));
    end;
    Entry.AddPair('needs', Needs);
    List.AddElement(Entry);
  end;
  Result.AddPair('candidates', List);
  Targets := TJSONArray.Create;
  for Hit in Hits do
  begin
    Entry := TJSONObject.Create;
    Entry.AddPair('name', Hit.Ref.ClassName);
    Entry.AddPair('unit', Hit.UnitName);
    Entry.AddPair('checked', TJSONBool.Create(not Up or (Targets.Count = 0)));
    Targets.AddElement(Entry);
  end;
  Result.AddPair('targets', Targets);
  Result.AddPair('multiTarget', TJSONBool.Create(not Up));
  // Nach unten bleiben benutzte Mitglieder oben (sie werden bei Bedarf sichtbar gemacht).
  Result.AddPair('needsRequired', TJSONBool.Create(Up));
  Option := TJSONObject.Create;
  if Up then
  begin
    Option.AddPair('kind', 'overrideSiblings');
  end
  else
  begin
    Option.AddPair('kind', 'keepAbstract');
  end;
  Option.AddPair('value', TJSONBool.Create(Up));
  Result.AddPair('option', Option);
  Result.AddPair('notes', TJSONArray.Create);
end;

function Ids(AObject: TJSONObject; const AKey: string): TArray<Integer>;
var
  Value, Item: TJSONValue;
begin
  Result := nil;
  Value := AObject.GetValue(AKey);
  if Value is TJSONArray then
  begin
    for Item in TJSONArray(Value) do
    begin
      if Item is TJSONNumber then
      begin
        Result := Result + [TJSONNumber(Item).AsInt];
      end;
    end;
  end;
end;

function Names(AObject: TJSONObject; const AKey: string): TArray<string>;
var
  Value, Item: TJSONValue;
begin
  Result := nil;
  Value := AObject.GetValue(AKey);
  if Value is TJSONArray then
  begin
    for Item in TJSONArray(Value) do
    begin
      Result := Result + [Trim(Item.Value)];
    end;
  end;
end;

/// <summary>Text der Datei; EJsonRpcError, wenn sie nicht lesbar ist.</summary>
function ReadFile(const AContext: TMoveMemberContext; const AFileName: string): string;
begin
  if not (Assigned(AContext.ReadText) and AContext.ReadText(AFileName, Result)) then
  begin
    raise Failed(Format('%s lässt sich nicht lesen.', [ExtractFileName(AFileName)]));
  end;
end;

type
  TLineRange = record
    FileName: string;
    First: Integer;
    Last: Integer;
  end;

/// <summary>Zeilen der Klasse und ihrer Rümpfe.</summary>
function ClassRanges(ALayout: TClassLayout; const AFileName: string): TArray<TLineRange>;
var
  Member: TClassMember;
  Range: TLineRange;
begin
  Range.FileName := AFileName;
  Range.First := ALayout.FirstLine;
  Range.Last := ALayout.EndLine;
  Result := [Range];
  for Member in ALayout.Members do
  begin
    if Member.Body <> nil then
    begin
      Range.First := Member.BodyFirstLine;
      Range.Last := Member.BodyLastLine;
      Result := Result + [Range];
    end;
  end;
end;

function InRanges(const ARanges: TArray<TLineRange>; const AFileName: string; ALine: Integer): Boolean;
var
  Range: TLineRange;
begin
  for Range in ARanges do
  begin
    if SameText(Range.FileName, AFileName) and (ALine >= Range.First) and (ALine <= Range.Last) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Position des Namens AName im Knoten ANode.</summary>
function NamePosition(ATree: TSyntaxTree; ANode: TSyntaxNode; const AName: string): TTextPosition;
var
  mIndex: Integer;
begin
  // Binär zum ersten Token des Knotens statt ab Dateianfang (#1323).
  mIndex := ATree.FirstTokenFrom(ANode.StartOffset);
  while (mIndex <= High(ATree.Tokens)) and (ATree.Tokens[mIndex].Offset < ANode.EndOffset) do
  begin
    if (ATree.Tokens[mIndex].Kind = TPascalTokenKind.Identifier) and SameText(ATree.Tokens[mIndex].Text, AName) then
    begin
      Exit(ATree.Tokens[mIndex].StartPos);
    end;
    Inc(mIndex);
  end;
  Result := ANode.StartPos;
end;

/// <summary>Namen, die ANode benutzt, mit ihrer Stelle (Bezeichner und Typverweise).</summary>
procedure CollectNames(ANode: TSyntaxNode; var ANames: TArray<TArray<string>>; var AOffsets: TArray<Integer>);
var
  Index: Integer;
  Name: string;
begin
  if ANode = nil then
  begin
    Exit;
  end;
  if (ANode.Kind = TSyntaxKind.Identifier) and ((ANode.Parent = nil) or
    (ANode.Parent.Kind <> TSyntaxKind.GenericParams)) then
  begin
    Name := ANode.Name;
    if Name.StartsWith('&') then
    begin
      Name := Name.Substring(1);
    end;
    ANames := ANames + [TArray<string>.Create(Name)];
    AOffsets := AOffsets + [ANode.StartOffset];
  end
  else if (ANode.Kind = TSyntaxKind.TypeReference) and (ANode.Name <> '') then
  begin
    ANames := ANames + [ANode.Name.Split(['.'])];
    AOffsets := AOffsets + [ANode.StartOffset];
  end;
  for Index := 0 to ANode.ChildCount - 1 do
  begin
    CollectNames(ANode[Index], ANames, AOffsets);
  end;
end;

function SectionLine(ATree: TSyntaxTree; AKind: TSyntaxKind): Integer;
var
  Index: Integer;
begin
  for Index := 0 to ATree.Root.ChildCount - 1 do
  begin
    if ATree.Root[Index].Kind = AKind then
    begin
      Exit(ATree.Root[Index].StartPos.Line);
    end;
  end;
  Result := -1;
end;

function SectionOffset(ATree: TSyntaxTree; AKind: TSyntaxKind): Integer;
var
  Index: Integer;
begin
  for Index := 0 to ATree.Root.ChildCount - 1 do
  begin
    if ATree.Root[Index].Kind = AKind then
    begin
      Exit(ATree.Root[Index].StartOffset + 1);
    end;
  end;
  Result := -1;
end;

/// <summary>Ergänzt in der Ziel-Unit AFiles[ATarget.FileName] die uses für die Namen, die die Deklarationen der
/// Mitglieder AIds und die Rümpfe von ABodyIds aus ASource benutzen. AUp: Die Ziel-Unit ist Vorfahr (darf die
/// Quelle nicht im interface einbinden).</summary>
procedure AddUses(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string; ASource: TClassLayout;
  const AIds, ABodyIds: TArray<Integer>; AFiles: TMemberFiles; const ATarget: TMemberClassRef; AUp: Boolean);
var
  Lookup: TMoveClassLookup;
  Meaning: TMoveClassMeaning;
  SourceUnit, TargetUnit, Text, LineBreak, Display: string;
  Ranges: TArray<TLineRange>;
  Pass, Index, Id, ImplementationLine, Offset: Integer;
  Node: TSyntaxNode;
  NameList: TArray<TArray<string>>;
  Offsets: TArray<Integer>;
  InInterface: Boolean;
  InterfaceUnits, ImplementationUnits, Missing: TArray<string>;
  TargetTree: TSyntaxTree;
  Target: TClassLayout;
  Edit: TTextEdit;
  Edits: TArray<TTextEdit>;
  Used: TArray<string>;
begin
  SourceUnit := TUsesClauses.OwnName(ATree.Tokens);
  Ranges := ClassRanges(ASource, AFileName);
  ImplementationLine := SectionLine(ATree, TSyntaxKind.ImplementationSection);
  Target := TMemberTransfer.ParseLayout(AFiles.Text(ATarget.FileName), ATarget.ClassName, TargetTree);
  if Target = nil then
  begin
    raise Failed(Format('%s ist nach dem Umbau nicht mehr lesbar.', [ATarget.ClassName]));
  end;
  try
    TargetUnit := TUsesClauses.OwnName(TargetTree.Tokens);
    InInterface := Target.InInterface;
    InterfaceUnits := nil;
    ImplementationUnits := nil;
    Lookup := TLspMoveClass.Lookup(AResolver);
    AResolver.PinTree(ATree, AFileName);
    try
      for Id in AIds do
      begin
        for Pass := 0 to 1 do
        begin
          // Erst die Deklaration, dann der Rumpf.
          if Pass = 0 then
          begin
            Node := ASource.Members[Id].Node;
          end
          else if TMemberTransfer.Has(ABodyIds, Id) then
          begin
            Node := ASource.Members[Id].Body;
          end
          else
          begin
            Node := nil;
          end;
          NameList := nil;
          Offsets := nil;
          CollectNames(Node, NameList, Offsets);
          for Index := 0 to High(NameList) do
          begin
            Meaning := Lookup(ATree, AFileName, NameList[Index], Offsets[Index]);
            if not Meaning.Found or Meaning.IsLocal or (Meaning.UnitName = '') or
              SameText(Meaning.UnitName, 'System') or SameText(Meaning.UnitName, TargetUnit) then
            begin
              Continue;
            end;
            // Mitglieder der Klasse selbst (sie wandern mit oder sind geerbt).
            if SameText(Meaning.FileName, AFileName) and InRanges(Ranges, AFileName, Meaning.Position.Line) then
            begin
              Continue;
            end;
            Display := string.Join('.', NameList[Index]);
            if SameText(Meaning.UnitName, SourceUnit) then
            begin
              if (ImplementationLine >= 0) and (Meaning.Position.Line > ImplementationLine) then
              begin
                raise Failed(Format('%s steht nur im implementation-Teil von %s und ist in %s nicht sichtbar.',
                  [Display, SourceUnit, TargetUnit]));
              end;
              // Nachfahren binden die Quelle ohnehin ein.
              if not AUp then
              begin
                Continue;
              end;
              if (Pass = 0) and InInterface then
              begin
                raise Failed(Format('%s stammt aus %s, die %s im interface einbinden müsste (Kreisverweis).',
                  [Display, SourceUnit, TargetUnit]));
              end;
              if IndexText(SourceUnit, ImplementationUnits) < 0 then
              begin
                ImplementationUnits := ImplementationUnits + [SourceUnit];
              end;
              Continue;
            end;
            if (Pass = 0) and InInterface then
            begin
              if IndexText(Meaning.UnitName, InterfaceUnits) < 0 then
              begin
                InterfaceUnits := InterfaceUnits + [Meaning.UnitName];
              end;
            end
            else if IndexText(Meaning.UnitName, ImplementationUnits) < 0 then
            begin
              ImplementationUnits := ImplementationUnits + [Meaning.UnitName];
            end;
          end;
        end;
      end;
    finally
      AResolver.UnpinTree;
    end;
    Text := AFiles.Text(ATarget.FileName);
    LineBreak := TTextLines.LineBreakOf(Text);
    Used := TUsesClauses.UsedUnits(TargetTree.Tokens);
    Edits := nil;
    Missing := nil;
    for Display in InterfaceUnits do
    begin
      if not TUsesClauses.IsUsed(Used, Display, nil) then
      begin
        Missing := Missing + [Display];
      end;
    end;
    Offset := SectionOffset(TargetTree, TSyntaxKind.InterfaceSection);
    if (Missing <> nil) and (Offset >= 0) and TUsesClauses.AddUnit(TargetTree.Tokens, Offset,
      string.Join(', ', Missing), LineBreak, Edit) then
    begin
      Edits := Edits + [Edit];
    end;
    Missing := nil;
    for Display in ImplementationUnits do
    begin
      if not TUsesClauses.IsUsed(Used, Display, nil) and (IndexText(Display, InterfaceUnits) < 0) then
      begin
        Missing := Missing + [Display];
      end;
    end;
    Offset := SectionOffset(TargetTree, TSyntaxKind.ImplementationSection);
    if (Missing <> nil) and (Offset >= 0) and TUsesClauses.AddUnit(TargetTree.Tokens, Offset,
      string.Join(', ', Missing), LineBreak, Edit) then
    begin
      Edits := Edits + [Edit];
    end;
    if Edits <> nil then
    begin
      AFiles.Put(ATarget.FileName, TTextChanges.Apply(Text, Edits));
    end;
  finally
    Target.Free;
    TargetTree.Free;
  end;
end;

/// <summary>Kopfzeile der Klasse AClassName in AText; 0 ohne.</summary>
function ClassLine(const AText, AClassName: string): Integer;
var
  Layout: TClassLayout;
  Tree: TSyntaxTree;
begin
  Result := 0;
  Layout := TMemberTransfer.ParseLayout(AText, AClassName, Tree);
  if Layout = nil then
  begin
    Exit;
  end;
  try
    Result := Layout.HeaderLine;
  finally
    Layout.Free;
    Tree.Free;
  end;
end;

/// <summary>Fehlerfrei parsen wie vorher; sonst EJsonRpcError mit der ersten Meldung.</summary>
procedure CheckParses(const AFileName, AOriginal, ANewText: string);
var
  Before, Check: TSyntaxTree;
begin
  Before := TSyntaxTreeCache.Parse(AOriginal);
  Check := TSyntaxTreeCache.Parse(ANewText);
  try
    if Length(Check.Diagnostics) > Length(Before.Diagnostics) then
    begin
      raise Failed(Format('Nach der Änderung parst %s nicht mehr fehlerfrei (Zeile %d: %s).',
        [ExtractFileName(AFileName), Check.Diagnostics[0].StartPos.Line + 1, Check.Diagnostics[0].Message]));
    end;
  finally
    Check.Free;
    Before.Free;
  end;
end;

class function TLspMoveMember.Execute(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName,
  AText: string; const APosition: TTextPosition; const ADirection: string; ARequest: TJSONValue;
  const AContext: TMoveMemberContext): TJSONObject;
var
  Body: TJSONObject;
  Up: Boolean;
  Found: TMoveMemberInfo;
  Request: TMoveMemberRequest;
  Plan: TMoveMemberPlan;
  Hits, Siblings: TArray<TClassHit>;
  Hit: TClassHit;
  Wanted: TArray<string>;
  Targets: TArray<TMemberClassRef>;
  Ref: TMemberClassRef;
  Files: TMemberFiles;
  Source, Layout: TClassLayout;
  Tree: TSyntaxTree;
  Ranges: TArray<TLineRange>;
  Id: Integer;
  BodyIds: TArray<Integer>;
  Location: TReferenceLocation;
  Reason, FileName, Warning, Description: string;
  Changes: TWorkspaceChanges;
begin
  if not (ARequest is TJSONObject) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, 'Anfrage mit members und targets fehlt');
  end;
  Body := TJSONObject(ARequest);
  Up := IsUp(ADirection);
  Found := Info(ATree, AText, APosition);
  Request := Default(TMoveMemberRequest);
  Request.Members := Ids(Body, 'members');
  Request.Abstract := Ids(Body, 'abstract');
  Request.RaiseVisibility := TClassVisibility.Protected_;
  Wanted := Names(Body, 'targets');
  if (Body.GetValue('option') is TJSONBool) and Up then
  begin
    Request.OverrideSiblings := TJSONBool(Body.GetValue('option')).AsBoolean;
  end
  else if Body.GetValue('option') is TJSONBool then
  begin
    Request.KeepAbstract := TJSONBool(Body.GetValue('option')).AsBoolean;
  end;
  if Up then
  begin
    Hits := AncestorChain(ATree, AText, AFileName, AContext.Index, Found.Ancestor);
  end
  else
  begin
    Hits := DirectDescendants(ATree, AText, AFileName, AContext.Index, Found.ClassName);
  end;
  Targets := nil;
  for Hit in Hits do
  begin
    if (IndexText(Hit.Ref.ClassName, Wanted) >= 0) and ((Targets = nil) or not Up) then
    begin
      Targets := Targets + [Hit.Ref];
    end;
  end;
  if Targets = nil then
  begin
    raise Failed('Bitte ein Ziel wählen, das im Projekt liegt.');
  end;
  Files := TMemberFiles.Create;
  Source := TClassLayout.Read(ATree, AText, TClassLayout.DeclNamed(ATree, Found.ClassName));
  Changes := TWorkspaceChanges.Create;
  try
    Files.Add(AFileName, AText);
    for Ref in Targets do
    begin
      if not Files.Has(Ref.FileName) then
      begin
        Files.Add(Ref.FileName, ReadFile(AContext, Ref.FileName));
      end;
    end;
    if Up then
    begin
      // Andere Nachfahren des Ziels (für override).
      Siblings := DirectDescendants(ATree, AText, AFileName, AContext.Index, Targets[0].ClassName);
      for Hit in Siblings do
      begin
        if not Files.Has(Hit.Ref.FileName) then
        begin
          Files.Add(Hit.Ref.FileName, ReadFile(AContext, Hit.Ref.FileName));
        end;
        Request.Siblings := Request.Siblings + [Hit.Ref];
      end;
      if not TMoveMember.PullUp(Files, TMemberClassRef.Create(AFileName, Found.ClassName), Targets[0], Request,
        Plan, Reason) then
      begin
        raise Failed(Reason);
      end;
    end
    else
    begin
      Request.AllTargets := Length(Hits);
      // Verweise außerhalb der Klasse und der gewählten Nachfahren.
      Ranges := ClassRanges(Source, AFileName);
      for Ref in Targets do
      begin
        Layout := TMemberTransfer.ParseLayout(Files.Text(Ref.FileName), Ref.ClassName, Tree);
        if Layout = nil then
        begin
          Continue;
        end;
        try
          Ranges := Ranges + ClassRanges(Layout, Ref.FileName);
        finally
          Layout.Free;
          Tree.Free;
        end;
      end;
      for Id in Request.Members do
      begin
        if (Id < 0) or (Id > High(Source.Members)) then
        begin
          Continue;
        end;
        for Location in TLspReferences.Find(AResolver, AContext.Index, ATree, AFileName,
          NamePosition(ATree, Source.Members[Id].Node, Source.Members[Id].Name), False, AContext.Files,
          AContext.ReadText) do
        begin
          if not InRanges(Ranges, Location.FileName, Location.Range.StartPos.Line) then
          begin
            Request.Usages := Request.Usages + [TMemberUsage.Create(Id, Format('%s:%d',
              [ExtractFileName(Location.FileName), Location.Range.StartPos.Line + 1]))];
          end;
        end;
      end;
      if not TMoveMember.PushDown(Files, TMemberClassRef.Create(AFileName, Found.ClassName), Targets, Request,
        Plan, Reason) then
      begin
        raise Failed(Reason);
      end;
    end;
    // uses der Ziele in anderen Units; abstrakt nach oben wandert nur die Deklaration.
    BodyIds := nil;
    for Id in Request.Members do
    begin
      if not (Up and TMemberTransfer.Has(Request.Abstract, Id)) then
      begin
        BodyIds := BodyIds + [Id];
      end;
    end;
    for Ref in Targets do
    begin
      if not SameText(Ref.FileName, AFileName) then
      begin
        AddUses(AResolver, ATree, AFileName, Source, Request.Members, BodyIds, Files, Ref, Up);
      end;
    end;
    for Warning in Plan.Warnings do
    begin
      Changes.Warn(Warning);
    end;
    for FileName in Files.Files do
    begin
      if Files.Changed(FileName) then
      begin
        CheckParses(FileName, Files.Original(FileName), Files.Text(FileName));
        Changes.Add(FileName, TTextChanges.Diff(Files.Original(FileName), Files.Text(FileName)));
      end;
    end;
    Description := Format('%d Mitglieder, %d Dateien', [Length(Plan.Moved) + Length(Plan.Abstracts),
      Changes.FileCount]);
    Result := TJSONObject.Create;
    Result.AddPair('edit', Changes.ToJson(AnnotationId, 'Mitglied verschieben', Description));
    Result.AddPair('warnings', Changes.WarningsJson);
    Result.AddPair('file', TDocumentUris.FromPath(Targets[0].FileName));
    Result.AddPair('line', TJSONNumber.Create(ClassLine(Files.Text(Targets[0].FileName), Targets[0].ClassName)));
    Result.AddPair('moved', TJSONNumber.Create(Length(Plan.Moved) + Length(Plan.Abstracts)));
  finally
    Changes.Free;
    Source.Free;
    Files.Free;
  end;
end;

end.
