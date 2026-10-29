unit Atlas.Common.Rules.Builtin.Automation;

// Regel zur OLE-Automation (#1373, Gruppe Compiler vorab):
//   automation-invalid
//                     Abschnitt automated einer Klasse: Felder (wie E2175),
//                     Konstruktoren und Destruktoren (wie E2177), dynamic und
//                     message (wie E2178), andere Aufrufkonventionen als
//                     register (wie E2179), dieselbe dispid zweimal in einer
//                     Klasse (wie E2180), Neudeklaration einer Property ohne
//                     Typ (wie E2181), index, stored, default und nodefault an
//                     Properties (wie E2182), read bzw. write auf ein Feld der
//                     Klasse (wie E2096), dispid an einer override-Methode
//                     (wie E2185) sowie Records, Zeiger und Mengen als Typ von
//                     Parametern, Ergebnissen und Properties (wie E2176).
//                     dispid an einer Methode außerhalb von automated meldet
//                     Delphi 13 als E2185 (nicht E2183, Fall Cm.E2183).
//                     Aufrufe über Variant bzw. OleVariant (V.Machen(...),
//                     auch V.Dokument.Oeffnen(...)): ein Record (ohne
//                     Operatoren) oder ein Zeiger als Argument (wie E2160 bei
//                     OleVariant, wie E2281 bei Variant) und ein unbenanntes
//                     Argument nach einem benannten (wie E2166).
//                     Mitglieder in bedingten Zweigen bleiben still; Typen,
//                     die die Namensauflösung nicht sicher kennt, ebenso.

interface

uses
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

const
  AutomationInvalidRuleId = 'automation-invalid';

type
  TAutomationInvalidRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

procedure RegisterAutomationRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.ConditionalBranches,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Semantics.ConstantValues;

const
  // Aufrufkonventionen, die im Abschnitt automated nicht erlaubt sind (E2179).
  cForeignConventions: array[0..4] of string = ('stdcall', 'cdecl', 'pascal', 'safecall', 'winapi');
  // Property-Klauseln, die im Abschnitt automated nicht erlaubt sind (E2182).
  cForbiddenClauses: array[0..3] of string = ('index', 'stored', 'default', 'nodefault');
  // Klauseln einer Property, hinter denen ein Argument steht.
  cArgumentClauses: array[0..6] of string = ('read', 'write', 'index', 'stored', 'default', 'implements', 'dispid');
  // Zeichentypen: ein Zeiger darauf (PChar) bleibt still.
  cCharTypes: array[0..3] of string = ('Char', 'AnsiChar', 'WideChar', 'UTF8Char');

type
  /// <summary>Eine dispid im Abschnitt automated: Schlüssel des Werts, Name des Mitglieds.</summary>
  TAutomationDispid = record
    Key: string;
    Member: string;
  end;

  /// <summary>Prüfung einer Datei; pinnt den Baum für die Dauer der Prüfung.</summary>
  TAutomationCheck = class
  private
    FContext: TRuleContext;
    FReport: IRuleReport;
    FTokens: TArray<TPascalToken>;
    FPaths: TArray<string>;
    FFileName: string;
    FResolver: TNameResolver;
    FOwnUnit: TUnitIndex;
    function FirstToken(ANode: TSyntaxNode): Integer;
    function StopToken(ANode: TSyntaxNode): Integer;
    function NextCode(AIndex, AStop: Integer): Integer;
    function PreviousCode(AIndex: Integer): Integer;
    function Unconditional(ANode: TSyntaxNode): Boolean;
    function TokenRange(AIndex: Integer): TTextRange;
    function NodeText(ANode: TSyntaxNode): string;
    /// <summary>Erstes Token mit dem Namen ANode.Name (bei Feldern der erste Name) ab dem Anfang des Knotens.
    /// </summary>
    function NameRange(ANode: TSyntaxNode): TTextRange;
    /// <summary>Text der Token AFirst..AStop-1 ohne Kommentare und Leerraum.</summary>
    function TokenText(AFirst, AStop: Integer): string;
    function HasDirective(AHeader: TSyntaxNode; const AName: string): Boolean;
    /// <summary>Typ ATypeNode, wenn er im Abschnitt automated sicher nicht erlaubt ist: Record, Zeiger, Menge.
    /// </summary>
    function IllegalAutomatedType(ATypeNode: TSyntaxNode; out AName: string): Boolean;
    procedure CheckTypes(AMember: TSyntaxNode);
    procedure CheckRoutine(AHeader: TSyntaxNode; ADispids: TList<TAutomationDispid>);
    procedure CheckProperty(AClass, AProperty: TSyntaxNode; ADispids: TList<TAutomationDispid>);
    /// <summary>dispid mit dem Argument AText an ARange für das Mitglied AMember; meldet eine doppelte.</summary>
    procedure CheckDispid(const ARange: TTextRange; const AText, AMember: string; ADispids: TList<TAutomationDispid>);
    procedure CheckClass(AClass: TSyntaxNode);
    /// <summary>Ist ANode ein Ausdruck vom Typ Variant bzw. OleVariant (auch über eine Kette von Aufrufen
    /// darauf)?</summary>
    function VariantReceiver(ANode: TSyntaxNode; out AOle: Boolean): Boolean;
    /// <summary>Typ des Arguments AArgument, wenn er sicher nicht über Variant aufgerufen werden kann.</summary>
    function IllegalDispatchArgument(AArgument: TSyntaxNode; out AName: string): Boolean;
    function NamedArgument(AArgument: TSyntaxNode): Boolean;
    procedure CheckDispatchCall(ACall: TSyntaxNode);
  public
    constructor Create(const AContext: TRuleContext; const AReport: IRuleReport);
    destructor Destroy; override;
    procedure Run;
  end;

function IsTrivia(const AToken: TPascalToken): Boolean;
begin
  Result := AToken.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive];
end;

/// <summary>Alle Knoten unter ARoot in Baumreihenfolge über einen eigenen Stapel (Bericht M1).</summary>
function PreOrder(ARoot: TSyntaxNode): TArray<TSyntaxNode>;
var
  mPending: TStack<TSyntaxNode>;
  mNodes: TList<TSyntaxNode>;
  mNode: TSyntaxNode;
  mIndex: Integer;
begin
  Result := nil;
  mPending := TStack<TSyntaxNode>.Create;
  mNodes := TList<TSyntaxNode>.Create;
  try
    mPending.Push(ARoot);
    while mPending.Count > 0 do
    begin
      mNode := mPending.Pop;
      mNodes.Add(mNode);
      for mIndex := mNode.ChildCount - 1 downto 0 do
        mPending.Push(mNode[mIndex]);
    end;
    Result := mNodes.ToArray;
  finally
    mNodes.Free;
    mPending.Free;
  end;
end;

/// <summary>Wert einer Zahl als Text (dezimal oder $-hex); '' bei anderem Text.</summary>
function NumberKey(const AText: string): string;
var
  mValue: Int64;
begin
  Result := '';
  if (AText <> '') and TryStrToInt64(AText, mValue) then
    Result := IntToStr(mValue);
end;

{ TAutomationCheck }

constructor TAutomationCheck.Create(const AContext: TRuleContext; const AReport: IRuleReport);
begin
  inherited Create;
  FContext := AContext;
  FReport := AReport;
  FTokens := AContext.Tree.Tokens;
  FPaths := TConditionalBranches.Paths(FTokens);
  FFileName := AContext.FileName;
  if FFileName = '' then
    FFileName := AContext.RelativePath;
  if FFileName = '' then
    FFileName := AContext.UnitName + '.pas';
  FResolver := TNameResolver.Create(AContext.Index, AContext.EnsureUnit, AContext.TreeUnits);
  FResolver.Namespaces := AContext.Namespaces;
  FResolver.PinTree(AContext.Tree, FFileName);
  FOwnUnit := FResolver.ExtractedUnit(AContext.Tree, FFileName);
end;

destructor TAutomationCheck.Destroy;
begin
  FResolver.UnpinTree;
  FResolver.Free;
  FTokens := nil;
  FPaths := nil;
  inherited;
end;

function TAutomationCheck.FirstToken(ANode: TSyntaxNode): Integer;
begin
  Result := TConstantValues.TokenFrom(FTokens, ANode.StartOffset);
end;

function TAutomationCheck.StopToken(ANode: TSyntaxNode): Integer;
begin
  Result := TConstantValues.TokenFrom(FTokens, ANode.EndOffset);
end;

function TAutomationCheck.NextCode(AIndex, AStop: Integer): Integer;
begin
  Result := AIndex;
  while (Result < AStop) and IsTrivia(FTokens[Result]) do
    Inc(Result);
end;

function TAutomationCheck.PreviousCode(AIndex: Integer): Integer;
begin
  Result := AIndex - 1;
  while (Result >= 0) and IsTrivia(FTokens[Result]) do
    Dec(Result);
end;

function TAutomationCheck.Unconditional(ANode: TSyntaxNode): Boolean;
begin
  Result := TConditionalBranches.PathAt(FPaths, FirstToken(ANode)) = '';
end;

function TAutomationCheck.TokenRange(AIndex: Integer): TTextRange;
begin
  Result := TTextRange.Create(FTokens[AIndex].StartPos, FTokens[AIndex].EndPos);
end;

function TAutomationCheck.NodeText(ANode: TSyntaxNode): string;
begin
  Result := Copy(FContext.Text, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset);
end;

function TAutomationCheck.NameRange(ANode: TSyntaxNode): TTextRange;
var
  mIndex, mStop: Integer;
  mName: string;
begin
  mName := ANode.Name;
  if Pos(',', mName) > 0 then
    mName := Copy(mName, 1, Pos(',', mName) - 1);
  mStop := StopToken(ANode);
  for mIndex := FirstToken(ANode) to mStop - 1 do
    if (FTokens[mIndex].Kind = TPascalTokenKind.Identifier) and SameText(FTokens[mIndex].Text, mName) then
      Exit(TokenRange(mIndex));
  Result := TTextRange.Create(ANode.StartPos, ANode.EndPos);
end;

function TAutomationCheck.TokenText(AFirst, AStop: Integer): string;
var
  mIndex: Integer;
begin
  Result := '';
  for mIndex := AFirst to AStop - 1 do
    if not IsTrivia(FTokens[mIndex]) then
      Result := Result + FTokens[mIndex].Text;
end;

function TAutomationCheck.HasDirective(AHeader: TSyntaxNode; const AName: string): Boolean;
var
  mIndex: Integer;
begin
  Result := False;
  for mIndex := 0 to AHeader.ChildCount - 1 do
    if (AHeader[mIndex].Kind = TSyntaxKind.Directive) and SameText(AHeader[mIndex].Name, AName) then
      Exit(True);
end;

function TAutomationCheck.IllegalAutomatedType(ATypeNode: TSyntaxNode; out AName: string): Boolean;
var
  mSymbol: TResolvedSymbol;
  mText, mDeclared: string;
begin
  Result := False;
  AName := Trim(NodeText(ATypeNode));
  if (ATypeNode.Kind <> TSyntaxKind.TypeReference) or (AName = '') or
    not FResolver.ResolveTypeTextFrom(FOwnUnit, AName, mSymbol) or (mSymbol.Condition <> '') then
    Exit;
  if mSymbol.Builtin then
    Exit(SameText(mSymbol.Name, 'Pointer'));
  if mSymbol.SymbolKind = TIndexSymbolKind.RecordType then
    Exit(True);
  if mSymbol.SymbolKind <> TIndexSymbolKind.TypeAlias then
    Exit;
  // Zeiger (PPunkt = ^TPunkt) und Mengen (TFarben = set of TFarbe) aus dem Kopf der Deklaration.
  mText := mSymbol.Signature;
  if Pos('=', mText) = 0 then
    Exit;
  mDeclared := Trim(Copy(mText, Pos('=', mText) + 1, MaxInt));
  if EndsStr(';', mDeclared) then
    mDeclared := Trim(Copy(mDeclared, 1, Length(mDeclared) - 1));
  if StartsStr('^', mDeclared) then
    Result := not MatchText(Trim(Copy(mDeclared, 2, MaxInt)), cCharTypes)
  else
    Result := StartsText('set of ', mDeclared);
end;

procedure TAutomationCheck.CheckTypes(AMember: TSyntaxNode);
var
  mTypes: TList<TSyntaxNode>;
  mParameters, mTypeNode: TSyntaxNode;
  mIndex, mInner: Integer;
  mName: string;
begin
  mTypes := TList<TSyntaxNode>.Create;
  try
    for mIndex := 0 to AMember.ChildCount - 1 do
      if AMember[mIndex].Kind = TSyntaxKind.TypeReference then
        mTypes.Add(AMember[mIndex])
      else if AMember[mIndex].Kind = TSyntaxKind.Parameters then
      begin
        mParameters := AMember[mIndex];
        for mInner := 0 to mParameters.ChildCount - 1 do
          if (mParameters[mInner].Kind = TSyntaxKind.Parameter) and (mParameters[mInner].ChildCount > 0) then
            mTypes.Add(mParameters[mInner][0]);
      end;
    for mTypeNode in mTypes do
      if IllegalAutomatedType(mTypeNode, mName) then
        FReport.Add(TTextRange.Create(mTypeNode.StartPos, mTypeNode.EndPos),
          Format('Der Typ %s ist im Abschnitt automated nicht erlaubt (wie E2176).', [mName]));
  finally
    mTypes.Free;
  end;
end;

procedure TAutomationCheck.CheckDispid(const ARange: TTextRange; const AText, AMember: string;
  ADispids: TList<TAutomationDispid>);
var
  mDispid: TAutomationDispid;
  mKey: string;
begin
  // Schlüssel: der Wert einer Zahl, sonst der Text des Ausdrucks.
  mKey := NumberKey(AText);
  if mKey = '' then
    mKey := UpperCase(AText);
  if mKey = '' then
    Exit;
  for mDispid in ADispids do
    if mDispid.Key = mKey then
    begin
      FReport.Add(ARange, Format('dispid %s ist schon an %s vergeben (wie E2180).', [AText, mDispid.Member]));
      Exit;
    end;
  mDispid.Key := mKey;
  mDispid.Member := AMember;
  ADispids.Add(mDispid);
end;

procedure TAutomationCheck.CheckRoutine(AHeader: TSyntaxNode; ADispids: TList<TAutomationDispid>);
var
  mFirst: Integer;
  mWord: string;
  mIndex: Integer;
  mDirective: TSyntaxNode;
begin
  mFirst := NextCode(FirstToken(AHeader), StopToken(AHeader));
  mWord := LowerCase(FTokens[mFirst].Text);
  if (mWord = 'constructor') or (mWord = 'destructor') then
    FReport.Add(TokenRange(mFirst),
      'Konstruktoren und Destruktoren sind im Abschnitt automated nicht erlaubt (wie E2177).');
  for mIndex := 0 to AHeader.ChildCount - 1 do
  begin
    mDirective := AHeader[mIndex];
    if mDirective.Kind <> TSyntaxKind.Directive then
      Continue;
    if MatchText(mDirective.Name, ['dynamic', 'message']) then
      FReport.Add(TokenRange(FirstToken(mDirective)),
        Format('%s ist im Abschnitt automated nicht erlaubt (wie E2178).', [mDirective.Name]))
    else if MatchText(mDirective.Name, cForeignConventions) then
      FReport.Add(TokenRange(FirstToken(mDirective)),
        Format('Im Abschnitt automated ist nur register erlaubt, nicht %s (wie E2179).', [mDirective.Name]))
    else if SameText(mDirective.Name, 'dispid') then
    begin
      if HasDirective(AHeader, 'override') then
        FReport.Add(TTextRange.Create(mDirective.StartPos, mDirective.EndPos),
          Format('Die überschriebene Methode %s übernimmt die dispid des Vorfahren und darf keine eigene ' +
          'angeben (wie E2185).', [AHeader.Name]))
      else
        CheckDispid(TTextRange.Create(mDirective.StartPos, mDirective.EndPos),
          TokenText(FirstToken(mDirective) + 1, StopToken(mDirective)), AHeader.Name, ADispids);
    end;
  end;
  CheckTypes(AHeader);
end;

procedure TAutomationCheck.CheckProperty(AClass, AProperty: TSyntaxNode; ADispids: TList<TAutomationDispid>);
var
  mIndex, mStop, mDepth, mArgument, mNext: Integer;
  mWord: string;
  mTyped, mExpectArgument: Boolean;

  function IsClassField(const AName: string): Boolean;
  var
    mMember: Integer;
    mNames: TArray<string>;
  begin
    Result := False;
    for mMember := 0 to AClass.ChildCount - 1 do
      if AClass[mMember].Kind = TSyntaxKind.Field then
      begin
        mNames := AClass[mMember].Name.Split([',']);
        if MatchText(AName, mNames) then
          Exit(True);
      end;
  end;

begin
  mTyped := AProperty.FindChild(TSyntaxKind.TypeReference) <> nil;
  if not mTyped then
    FReport.Add(NameRange(AProperty),
      Format('Die Property %s darf im Abschnitt automated nicht ohne Typ neu deklariert werden (wie E2181).',
      [AProperty.Name]));
  // Klauseln hinter dem Typ bis zum ersten Semikolon auf Klammerebene 0.
  mIndex := FirstToken(AProperty);
  mStop := StopToken(AProperty);
  while (mIndex < mStop) and not ((FTokens[mIndex].Kind = TPascalTokenKind.Identifier) and
    SameText(FTokens[mIndex].Text, AProperty.Name)) do
    Inc(mIndex);
  mDepth := 0;
  mExpectArgument := False;
  Inc(mIndex);
  while mIndex < mStop do
  begin
    if IsTrivia(FTokens[mIndex]) then
    begin
      Inc(mIndex);
      Continue;
    end;
    if FTokens[mIndex].IsSymbol('[') or FTokens[mIndex].IsSymbol('(') then
      Inc(mDepth)
    else if FTokens[mIndex].IsSymbol(']') or FTokens[mIndex].IsSymbol(')') then
      Dec(mDepth)
    else if (mDepth = 0) and FTokens[mIndex].IsSymbol(';') then
      Break
    else if (mDepth = 0) and not mExpectArgument and (FTokens[mIndex].Kind = TPascalTokenKind.Identifier) then
    begin
      mWord := LowerCase(FTokens[mIndex].Text);
      if MatchText(mWord, cForbiddenClauses) then
        FReport.Add(TokenRange(mIndex),
          Format('%s ist an Properties im Abschnitt automated nicht erlaubt (wie E2182).', [mWord]));
      if ((mWord = 'read') or (mWord = 'write')) and mTyped then
      begin
        mArgument := NextCode(mIndex + 1, mStop);
        mNext := NextCode(mArgument + 1, mStop);
        // read FPunkt.X ist ein Feldzugriff, aber nicht sicher dasselbe Feld.
        if (mArgument < mStop) and (FTokens[mArgument].Kind = TPascalTokenKind.Identifier) and
          ((mNext >= mStop) or not FTokens[mNext].IsSymbol('.')) and IsClassField(FTokens[mArgument].Text) then
          FReport.Add(TokenRange(mArgument),
            Format('Im Abschnitt automated muss %s auf eine Methode zeigen; %s ist ein Feld (wie E2096).',
            [mWord, FTokens[mArgument].Text]));
      end;
      if mWord = 'dispid' then
      begin
        // Argument bis zur nächsten Klausel bzw. zum Semikolon.
        mArgument := mIndex + 1;
        while (mArgument < mStop) and not FTokens[mArgument].IsSymbol(';') and
          not ((FTokens[mArgument].Kind = TPascalTokenKind.Identifier) and
          MatchText(FTokens[mArgument].Text, cArgumentClauses)) do
          Inc(mArgument);
        CheckDispid(TTextRange.Create(FTokens[mIndex].StartPos, FTokens[mArgument - 1].EndPos),
          TokenText(mIndex + 1, mArgument), AProperty.Name, ADispids);
      end;
      mExpectArgument := MatchText(mWord, cArgumentClauses);
      Inc(mIndex);
      Continue;
    end;
    mExpectArgument := False;
    Inc(mIndex);
  end;
  if mTyped then
    CheckTypes(AProperty);
end;

procedure TAutomationCheck.CheckClass(AClass: TSyntaxNode);
var
  mDispids: TList<TAutomationDispid>;
  mMember, mDirective: TSyntaxNode;
  mIndex, mInner: Integer;
  mAutomated: Boolean;
begin
  mDispids := TList<TAutomationDispid>.Create;
  try
    mAutomated := False;
    for mIndex := 0 to AClass.ChildCount - 1 do
    begin
      mMember := AClass[mIndex];
      if mMember.Kind = TSyntaxKind.Visibility then
      begin
        mAutomated := mMember.Name = 'automated';
        Continue;
      end;
      if not Unconditional(mMember) then
        Continue;
      if not mAutomated then
      begin
        // dispid außerhalb von automated: Delphi 13 meldet E2185 (Fall Cm.E2183).
        if mMember.Kind = TSyntaxKind.RoutineHeader then
          for mInner := 0 to mMember.ChildCount - 1 do
          begin
            mDirective := mMember[mInner];
            if (mDirective.Kind = TSyntaxKind.Directive) and SameText(mDirective.Name, 'dispid') then
              FReport.Add(TTextRange.Create(mDirective.StartPos, mDirective.EndPos),
                'dispid ist nur im Abschnitt automated erlaubt (wie E2185).');
          end;
        Continue;
      end;
      case mMember.Kind of
        TSyntaxKind.Field:
          FReport.Add(NameRange(mMember), 'Felder sind im Abschnitt automated nicht erlaubt (wie E2175).');
        TSyntaxKind.RoutineHeader:
          if not mMember.IsMethodResolution then
            CheckRoutine(mMember, mDispids);
        TSyntaxKind.PropertyDecl:
          CheckProperty(AClass, mMember, mDispids);
      else
        // Übrige Mitglieder (Konstanten, Typen, Attribute) bleiben still.
      end;
    end;
  finally
    mDispids.Free;
  end;
end;

function TAutomationCheck.VariantReceiver(ANode: TSyntaxNode; out AOle: Boolean): Boolean;
var
  mNode: TSyntaxNode;
  mSymbol, mType: TResolvedSymbol;
  mFound: Boolean;
begin
  Result := False;
  AOle := False;
  mNode := ANode;
  // Der Wert einer Kette auf einem Variant (V.Dokument.Seiten[1]) ist wieder ein Variant.
  while mNode <> nil do
  begin
    if FResolver.NodeType(FContext.Tree, FFileName, mNode, mSymbol, mType, mFound) then
    begin
      if not mFound or not mType.Builtin or (mSymbol.Condition <> '') then
        Exit;
      AOle := SameText(mType.Name, 'OleVariant');
      Exit(AOle or SameText(mType.Name, 'Variant'));
    end;
    if not (mNode.Kind in [TSyntaxKind.MemberAccess, TSyntaxKind.Call, TSyntaxKind.IndexAccess]) or
      (mNode.ChildCount = 0) then
      Exit;
    mNode := mNode[0];
  end;
end;

function TAutomationCheck.IllegalDispatchArgument(AArgument: TSyntaxNode; out AName: string): Boolean;
var
  mSymbol, mType, mOperator: TResolvedSymbol;
  mFound: Boolean;
  mDeclared: string;
begin
  Result := False;
  AName := '';
  if not (AArgument.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess, TSyntaxKind.IndexAccess]) or
    not FResolver.NodeType(FContext.Tree, FFileName, AArgument, mSymbol, mType, mFound) or not mFound or
    mSymbol.IsType or (mSymbol.Condition <> '') or (mSymbol.VariantBranch <> '') then
    Exit;
  AName := mType.Name;
  if mType.Builtin then
    Exit(SameText(mType.Name, 'Pointer'));
  if mType.SymbolKind = TIndexSymbolKind.RecordType then
    // Ein Record mit Operatoren (Implicit nach Variant?) bleibt still.
    Exit(not FResolver.FindMember(mType, 'Implicit', mOperator) and
      not FResolver.FindMember(mType, 'Explicit', mOperator));
  if mType.SymbolKind = TIndexSymbolKind.TypeAlias then
  begin
    mDeclared := mType.Signature;
    if Pos('=', mDeclared) = 0 then
      Exit;
    mDeclared := Trim(Copy(mDeclared, Pos('=', mDeclared) + 1, MaxInt));
    if EndsStr(';', mDeclared) then
      mDeclared := Trim(Copy(mDeclared, 1, Length(mDeclared) - 1));
    Result := StartsStr('^', mDeclared) and not MatchText(Trim(Copy(mDeclared, 2, MaxInt)), cCharTypes);
  end;
end;

function TAutomationCheck.NamedArgument(AArgument: TSyntaxNode): Boolean;
var
  mPrevious: Integer;
begin
  // Open(FileName := 'a.docx'): Der Parser legt für den Namen keinen Knoten an.
  mPrevious := PreviousCode(FirstToken(AArgument));
  Result := (mPrevious > 0) and FTokens[mPrevious].IsSymbol(':=');
end;

procedure TAutomationCheck.CheckDispatchCall(ACall: TSyntaxNode);
var
  mIndex: Integer;
  mOle, mNamedSeen: Boolean;
  mArgument: TSyntaxNode;
  mName, mCode, mKind: string;
begin
  if (ACall.ChildCount < 2) or (ACall[0].Kind <> TSyntaxKind.MemberAccess) or (ACall[0].ChildCount = 0) or
    not Unconditional(ACall) or not VariantReceiver(ACall[0][0], mOle) then
    Exit;
  if mOle then
  begin
    mCode := 'E2160';
    mKind := 'OLE-Automation-Aufruf';
  end
  else
  begin
    mCode := 'E2281';
    mKind := 'Variant-Dispatch-Aufruf';
  end;
  mNamedSeen := False;
  for mIndex := 1 to ACall.ChildCount - 1 do
  begin
    mArgument := ACall[mIndex];
    if NamedArgument(mArgument) then
      mNamedSeen := True
    else if mNamedSeen then
      FReport.Add(TTextRange.Create(mArgument.StartPos, mArgument.EndPos),
        'Unbenannte Argumente müssen vor den benannten stehen (wie E2166).');
    if IllegalDispatchArgument(mArgument, mName) then
      FReport.Add(TTextRange.Create(mArgument.StartPos, mArgument.EndPos),
        Format('Der Typ %s ist in einem %s nicht erlaubt (wie %s).', [mName, mKind, mCode]));
  end;
end;

procedure TAutomationCheck.Run;
var
  mNode: TSyntaxNode;
begin
  for mNode in PreOrder(FContext.Tree.Root) do
    case mNode.Kind of
      TSyntaxKind.ClassType:
        CheckClass(mNode);
      TSyntaxKind.Call:
        CheckDispatchCall(mNode);
    else
      // Übrige Knoten bewusst ohne Wirkung.
    end;
end;

{ TAutomationInvalidRule }

function TAutomationInvalidRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(AutomationInvalidRuleId, TRuleSeverity.Error,
    'OLE-Automation falsch deklariert oder aufgerufen');
end;

procedure TAutomationInvalidRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mCheck: TAutomationCheck;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
    Exit;
  mCheck := TAutomationCheck.Create(AContext, AReport);
  try
    mCheck.Run;
  finally
    mCheck.Free;
  end;
end;

procedure RegisterAutomationRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TAutomationInvalidRule.Create);
end;

end.
