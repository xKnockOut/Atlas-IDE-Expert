unit Atlas.Common.Lsp.CompletionUses;

// Vervollständigung im uses-Abschnitt (#469, ARG-070), mit completion.usesDetails:
// - Quelle ist der Unit-Index (#180). Reihenfolge nach Gruppen: Projekt-Units, RTL/VCL (Bibliotheks-Units mit
//   Embarcadero-Namespace oder aus dem Installationsordner von RAD Studio), Drittanbieter (übrige
//   Bibliotheks-Units); innerhalb der Gruppe nach Treffer, dann alphabetisch.
// - Das Getippte passt auch ab einem späteren Namensteil: "Gener" findet System.Generics.Collections,
//   "Classes" findet System.Classes. Teile, die einer der Unit-Namespaces des Projekts sind, gehen vor
//   anderen Namensteilen. Übernommen wird immer der volle Name (textEdit vom Anfang des getippten Namens).
// - Units der Liste am Cursor fehlen; die des anderen Abschnitts tragen den Hinweis „bereits im
//   interface-Teil“ bzw. „… implementation-Teil“. Welche fehlen, steht für die Fußzeile an jedem Eintrag.
// - Im interface-Teil einer Unit: Bindet eine Projekt-Unit die eigene Unit über ihre interface-uses ein
//   (direkt oder über weitere Units, soweit im Index), trägt sie den Zirkelbezug mit der Kette.
// - Detailpanel: Pfad (unter RAD Studio als $(BDS)\…) und die ersten exportierten Typen.

interface

{$SCOPEDENUMS ON}

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Lsp.CompletionRequest,
  Atlas.Common.Lsp.CompletionCollector;

type
  TUsesGroup = (Project, Rtl, Library_);

  /// <summary>Abschnitt der uses-Liste am Cursor; Other in Programmen, Packages und Bibliotheken.</summary>
  TUsesSection = (Other, Interface_, Implementation_);

  TUsesSite = record
    Section: TUsesSection;
    /// <summary>Units der Liste am Cursor (auch weiterer Listen desselben Abschnitts) ohne den angefangenen
    /// Namen.</summary>
    Here: TArray<string>;
    /// <summary>Units des anderen Abschnitts einer Unit.</summary>
    Other: TArray<string>;
  end;

  TUsesMatch = record
    /// <summary>Trefferwert nach MatchScore, abzüglich der Strafpunkte für einen späteren Namensteil.</summary>
    Score: Integer;
    /// <summary>Teil des Namens, gegen den der Editor das Wort hinter dem letzten Punkt filtert.</summary>
    Filter: string;
  end;

  TCompletionUses = class
  public const
    GroupNames: array[TUsesGroup] of string = ('project', 'rtl', 'library');
    SectionNames: array[TUsesSection] of string = ('', 'interface', 'implementation');
    /// <summary>Namespaces der Units, die RAD Studio mitbringt.</summary>
    RtlNamespaces: array[0..16] of string = ('System', 'Vcl', 'Winapi', 'Data', 'Xml', 'Soap', 'Web',
      'Datasnap', 'FMX', 'REST', 'FireDAC', 'IBX', 'Bde', 'Posix', 'Macapi', 'Androidapi', 'iOSapi');
    /// <summary>Abzug je Gruppe: Projekt vor RTL/VCL vor Drittanbietern, unabhängig vom Treffer.</summary>
    GroupPenalty = 10000;
    /// <summary>Abzug für einen Treffer ab einem Namensteil, der ein Namespace des Projekts ist, bzw. ab einem
    /// anderen Namensteil.</summary>
    NamespacePenalty = 5;
    PartPenalty = 20;
    MaxTypes = 6;
  public
    class function GroupOf(const AUnit: TUnitIndex): TUsesGroup; static;
    /// <summary>uses-Listen um APosition: Abschnitt, eingebundene Units hier und im anderen Abschnitt. Liest auch
    /// unvollständige Listen (ohne Semikolon) bis zum nächsten Schlüsselwort.</summary>
    class function SiteAt(const ATokens: TArray<TPascalToken>; const APosition: TTextPosition): TUsesSite; static;
    /// <summary>Passt APrefix zu AUnitName, ab dem Anfang oder einem späteren Namensteil? ANamespaces sind die
    /// Unit-Namespaces des Projekts.</summary>
    class function Match(const AUnitName, APrefix: string; const ANamespaces: TArray<string>;
      AMatching: TCompletionMatching; out AMatch: TUsesMatch): Boolean; static;
    /// <summary>Pfad für das Detailpanel: unter "…\Embarcadero\Studio\&lt;Version&gt;\" als "$(BDS)\…".</summary>
    class function ShortPath(const AFileName: string): string; static;
    /// <summary>Typen des interface-Teils in Deklarationsreihenfolge, generische mit Typparametern
    /// (TList&lt;T&gt;); höchstens AMax, ACount ist die Gesamtzahl.</summary>
    class function ExportedTypes(const AUnit: TUnitIndex; AMax: Integer; out ACount: Integer): TArray<string>;
      static;
    /// <summary>Projekt-Units, die AOwnUnit über interface-uses einbinden, je mit der Kette bis AOwnUnit
    /// ("uA → uB → Haupt"); Schlüssel in Großschreibung.</summary>
    class function Cycles(const AUnits: TArray<TUnitIndex>; const AOwnUnit: string;
      const ANamespaces: TArray<string>): TDictionary<string, string>; static;
    /// <summary>Eingebundene Units für die Fußzeile: die zum Getippten passenden, sonst alle der Liste.</summary>
    class function Hidden(const ASite: TUsesSite; const APrefix: string; const ANamespaces: TArray<string>;
      AMatching: TCompletionMatching): TArray<string>; static;
    /// <summary>Einträge für den uses-Abschnitt an ACollector.</summary>
    class procedure Collect(ARequest: TCompletionRequest; const AContext: TCompletionContext;
      ACollector: TCompletionCollector); static;
  end;

implementation

uses
  System.Math,
  System.StrUtils,
  System.Generics.Defaults,
  Atlas.Common.Editing.UsesClause,
  Atlas.Common.Lsp.FuzzyMatch;

function IsTrivia(const AToken: TPascalToken): Boolean;
begin
  Result := AToken.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive];
end;

/// <summary>A liegt vor B.</summary>
function Before(const A, B: TTextPosition): Boolean;
begin
  Result := (A.Line < B.Line) or (A.Line = B.Line) and (A.Character < B.Character);
end;

function JoinParts(const AParts: TArray<string>; AFrom: Integer): string;
var
  Index: Integer;
begin
  Result := '';
  for Index := AFrom to High(AParts) do
  begin
    if Result = '' then
    begin
      Result := AParts[Index];
    end
    else
    begin
      Result := Result + '.' + AParts[Index];
    end;
  end;
end;

{ TCompletionUses }

class function TCompletionUses.GroupOf(const AUnit: TUnitIndex): TUsesGroup;
var
  Namespace, Path, Known: string;
begin
  if not AUnit.Library_ then
  begin
    Exit(TUsesGroup.Project);
  end;
  Path := LowerCase(AUnit.FileName.Replace('/', '\'));
  if Pos('\embarcadero\studio\', Path) > 0 then
  begin
    Exit(TUsesGroup.Rtl);
  end;
  Namespace := '';
  if Pos('.', AUnit.UnitName) > 0 then
  begin
    Namespace := Copy(AUnit.UnitName, 1, Pos('.', AUnit.UnitName) - 1);
  end;
  for Known in RtlNamespaces do
  begin
    if SameText(Namespace, Known) then
    begin
      Exit(TUsesGroup.Rtl);
    end;
  end;
  Result := TUsesGroup.Library_;
end;

type
  /// <summary>Liest eine uses-Liste Token für Token.</summary>
  TClauseReader = record
    Names: TArray<string>;
    Name: string;
    // Der Name, an dem getippt wird, zählt nicht als eingebunden.
    Current: Boolean;
    AfterIn: Boolean;
    procedure Flush;
    /// <summary>Nimmt AToken auf; False am Ende der Liste (Semikolon bzw. fremdes Schlüsselwort).</summary>
    function Take(const AToken: TPascalToken; const APosition: TTextPosition): Boolean;
  end;

  /// <summary>Gelesene uses-Listen je Abschnitt.</summary>
  TSectionLists = record
    Interface_, Implementation_, Others: TArray<string>;
    procedure Add(ASection: TUsesSection; const ANames: TArray<string>);
    function Site(ASection: TUsesSection): TUsesSite;
  end;

procedure TClauseReader.Flush;
begin
  if (Name <> '') and not Current then
  begin
    Names := Names + [Name];
  end;
  Name := '';
  Current := False;
  AfterIn := False;
end;

function TClauseReader.Take(const AToken: TPascalToken; const APosition: TTextPosition): Boolean;
begin
  Result := True;
  if AToken.IsSymbol(',') then
  begin
    Flush;
  end
  else if AToken.IsSymbol(';') or (AToken.Kind = TPascalTokenKind.Keyword) and not AToken.IsKeyword('in') then
  begin
    Result := False;
  end
  else if AToken.IsKeyword('in') then
  begin
    AfterIn := True;
  end
  else if not AfterIn and ((AToken.Kind = TPascalTokenKind.Identifier) or AToken.IsSymbol('.')) then
  begin
    Name := Name + AToken.Text;
    Current := Current or (Before(AToken.StartPos, APosition) and not Before(AToken.EndPos, APosition));
  end;
end;

procedure TSectionLists.Add(ASection: TUsesSection; const ANames: TArray<string>);
begin
  case ASection of
    TUsesSection.Interface_:
      Interface_ := Interface_ + ANames;
    TUsesSection.Implementation_:
      Implementation_ := Implementation_ + ANames;
  else
    Others := Others + ANames;
  end;
end;

function TSectionLists.Site(ASection: TUsesSection): TUsesSite;
begin
  Result := Default(TUsesSite);
  Result.Section := ASection;
  case ASection of
    TUsesSection.Interface_:
      begin
        Result.Here := Interface_;
        Result.Other := Implementation_;
      end;
    TUsesSection.Implementation_:
      begin
        Result.Here := Implementation_;
        Result.Other := Interface_;
      end;
  else
    Result.Here := Others;
  end;
end;

/// <summary>Namen der uses-Liste ab AIndex (hinter "uses"); AIndex steht danach auf ihrem Ende (Semikolon bzw.
/// erstes fremdes Token).</summary>
function ReadClause(const ATokens: TArray<TPascalToken>; var AIndex: Integer;
  const APosition: TTextPosition): TArray<string>;
var
  mReader: TClauseReader;
begin
  mReader := Default(TClauseReader);
  while AIndex <= High(ATokens) do
  begin
    if not IsTrivia(ATokens[AIndex]) and not mReader.Take(ATokens[AIndex], APosition) then
    begin
      Break;
    end;
    Inc(AIndex);
  end;
  mReader.Flush;
  Result := mReader.Names;
end;

/// <summary>Beginnt der Text mit "unit"?</summary>
function IsUnitText(const ATokens: TArray<TPascalToken>): Boolean;
var
  mFirst: Integer;
begin
  mFirst := 0;
  while (mFirst <= High(ATokens)) and IsTrivia(ATokens[mFirst]) do
  begin
    Inc(mFirst);
  end;
  Result := (mFirst <= High(ATokens)) and ATokens[mFirst].IsKeyword('unit');
end;

function ClauseSectionOf(AIsUnit, AInImplementation: Boolean): TUsesSection;
begin
  Result := TUsesSection.Other;
  if AIsUnit and AInImplementation then
  begin
    Result := TUsesSection.Implementation_;
  end
  else if AIsUnit then
  begin
    Result := TUsesSection.Interface_;
  end;
end;

class function TCompletionUses.SiteAt(const ATokens: TArray<TPascalToken>; const APosition: TTextPosition): TUsesSite;
var
  mIndex: Integer;
  mIsUnit, mInImplementation, mAtCursor: Boolean;
  mLists: TSectionLists;
  mSection, mClause: TUsesSection;
  mNames: TArray<string>;
begin
  mLists := Default(TSectionLists);
  mSection := TUsesSection.Other;
  mIsUnit := IsUnitText(ATokens);
  mInImplementation := False;
  mIndex := 0;
  while mIndex <= High(ATokens) do
  begin
    if ATokens[mIndex].IsKeyword('implementation') then
    begin
      mInImplementation := True;
    end
    else if ATokens[mIndex].IsKeyword('uses') or ATokens[mIndex].IsKeyword('contains') then
    begin
      mClause := ClauseSectionOf(mIsUnit, mInImplementation);
      mAtCursor := not Before(APosition, ATokens[mIndex].EndPos);
      Inc(mIndex);
      mNames := ReadClause(ATokens, mIndex, APosition);
      // Cursor in dieser Liste: hinter "uses" und vor dem Ende (Semikolon bzw. erstes fremdes Token).
      if mAtCursor and ((mIndex > High(ATokens)) or not Before(ATokens[mIndex].StartPos, APosition)) then
      begin
        mSection := mClause;
      end;
      mLists.Add(mClause, mNames);
      Continue;
    end;
    Inc(mIndex);
  end;
  Result := mLists.Site(mSection);
end;

/// <summary>Abzug für einen Treffer ab Namensteil APart: keiner am Anfang, wenig hinter einem Namespace des
/// Projekts, sonst mehr.</summary>
function PartPenaltyOf(const AParts: TArray<string>; APart: Integer; const ANamespaces: TArray<string>): Integer;
var
  mLead, mNamespace: string;
begin
  Result := 0;
  if APart = 0 then
  begin
    Exit;
  end;
  Result := TCompletionUses.PartPenalty;
  mLead := JoinParts(Copy(AParts, 0, APart), 0);
  for mNamespace in ANamespaces do
  begin
    if SameText(mNamespace, mLead) then
    begin
      Result := TCompletionUses.NamespacePenalty;
    end;
  end;
end;

class function TCompletionUses.Match(const AUnitName, APrefix: string; const ANamespaces: TArray<string>;
  AMatching: TCompletionMatching; out AMatch: TUsesMatch): Boolean;
var
  mParts: TArray<string>;
  mPart, mDots, mScore: Integer;
begin
  AMatch := Default(TUsesMatch);
  AMatch.Score := TFuzzyMatch.NoMatch;
  mParts := AUnitName.Split(['.']);
  mDots := Length(APrefix) - Length(APrefix.Replace('.', ''));
  Result := False;
  for mPart := 0 to High(mParts) do
  begin
    // Ohne Eingabe nur der volle Name; sonst jede Stelle, an der ein Namensteil beginnt.
    if (APrefix = '') and (mPart > 0) then
    begin
      Break;
    end;
    mScore := MatchScore(JoinParts(mParts, mPart), APrefix, AMatching);
    if mScore = TFuzzyMatch.NoMatch then
    begin
      Continue;
    end;
    Dec(mScore, PartPenaltyOf(mParts, mPart, ANamespaces));
    if not Result or (mScore > AMatch.Score) then
    begin
      Result := True;
      AMatch.Score := mScore;
      AMatch.Filter := JoinParts(mParts, Min(mPart + mDots, High(mParts)));
    end;
  end;
end;

class function TCompletionUses.ShortPath(const AFileName: string): string;
const
  Marker = '\embarcadero\studio\';
var
  Path: string;
  Start, Stop: Integer;
begin
  Result := AFileName;
  Path := AFileName.Replace('/', '\');
  Start := Pos(Marker, LowerCase(Path));
  if Start = 0 then
  begin
    Exit;
  end;
  // Hinter "Studio\" steht die Version ("37.0"), dann der Rest unter $(BDS).
  Stop := PosEx('\', Path, Start + Length(Marker));
  if Stop = 0 then
  begin
    Exit;
  end;
  Result := '$(BDS)' + Copy(Path, Stop, MaxInt);
end;

class function TCompletionUses.ExportedTypes(const AUnit: TUnitIndex; AMax: Integer;
  out ACount: Integer): TArray<string>;
var
  Symbol: TIndexSymbol;
  Name: string;
begin
  Result := nil;
  ACount := 0;
  for Symbol in AUnit.Symbols do
  begin
    if not Symbol.InInterface or (Symbol.Container <> '') or not (Symbol.Kind in IndexTypeKinds) then
    begin
      Continue;
    end;
    Inc(ACount);
    if Length(Result) >= AMax then
    begin
      Continue;
    end;
    Name := Symbol.Name;
    if Symbol.TypeParams <> '' then
    begin
      Name := Name + '<' + Symbol.TypeParams.Replace(' ', '') + '>';
    end;
    Result := Result + [Name];
  end;
end;

/// <summary>Projekt-Units und AOwnUnit, je Großschreibung der Name. Bibliotheken binden keine Projekt-Units ein.
/// </summary>
function ProjectNames(const AUnits: TArray<TUnitIndex>; const AOwnUnit: string): TDictionary<string, string>;
var
  mUnitInfo: TUnitIndex;
begin
  Result := TDictionary<string, string>.Create;
  for mUnitInfo in AUnits do
  begin
    if not mUnitInfo.Library_ then
    begin
      Result.AddOrSetValue(UpperCase(mUnitInfo.UnitName), mUnitInfo.UnitName);
    end;
  end;
  Result.AddOrSetValue(UpperCase(AOwnUnit), AOwnUnit);
end;

/// <summary>Projekt-Unit zum Namen AName in uses, auch über die Namespaces; '' ohne.</summary>
function ResolveUnit(ANames: TDictionary<string, string>; const ANamespaces: TArray<string>;
  const AName: string): string;
var
  mNamespace: string;
begin
  if ANames.TryGetValue(UpperCase(AName), Result) then
  begin
    Exit;
  end;
  for mNamespace in ANamespaces do
  begin
    if ANames.TryGetValue(UpperCase(mNamespace + '.' + AName), Result) then
    begin
      Exit;
    end;
  end;
  Result := '';
end;

/// <summary>AUser als Nutzer von ATarget in AUsers eintragen.</summary>
procedure AddUser(AUsers: TObjectDictionary<string, TList<string>>; const ATarget, AUser: string);
var
  mList: TList<string>;
begin
  if not AUsers.TryGetValue(UpperCase(ATarget), mList) then
  begin
    mList := TList<string>.Create;
    AUsers.Add(UpperCase(ATarget), mList);
  end;
  mList.Add(AUser);
end;

/// <summary>Rückwärts: Je Projekt-Unit (Großschreibung) die Projekt-Units, die sie im interface-Teil einbinden.
/// </summary>
function InterfaceUsers(const AUnits: TArray<TUnitIndex>; const AOwnUnit: string;
  ANames: TDictionary<string, string>; const ANamespaces: TArray<string>): TObjectDictionary<string, TList<string>>;
var
  mUnitInfo: TUnitIndex;
  mUsed, mTarget: string;
begin
  Result := TObjectDictionary<string, TList<string>>.Create([doOwnsValues]);
  for mUnitInfo in AUnits do
  begin
    if mUnitInfo.Library_ or SameText(mUnitInfo.UnitName, AOwnUnit) then
    begin
      Continue;
    end;
    for mUsed in mUnitInfo.InterfaceUses do
    begin
      mTarget := ResolveUnit(ANames, ANamespaces, mUsed);
      if mTarget <> '' then
      begin
        AddUser(Result, mTarget, mUnitInfo.UnitName);
      end;
    end;
  end;
end;

/// <summary>Breitensuche ab AOwnUnit über AUsers: je erreichter Unit (Großschreibung) die nächste Unit der Kette
/// zurück zu AOwnUnit ('' für AOwnUnit selbst).</summary>
function ReachFrom(AUsers: TObjectDictionary<string, TList<string>>;
  const AOwnUnit: string): TDictionary<string, string>;
var
  mQueue: TQueue<string>;
  mCurrent, mUser: string;
  mList: TList<string>;
begin
  Result := TDictionary<string, string>.Create;
  mQueue := TQueue<string>.Create;
  try
    mQueue.Enqueue(AOwnUnit);
    Result.Add(UpperCase(AOwnUnit), '');
    while mQueue.Count > 0 do
    begin
      mCurrent := mQueue.Dequeue;
      if not AUsers.TryGetValue(UpperCase(mCurrent), mList) then
      begin
        Continue;
      end;
      for mUser in mList do
      begin
        if not Result.ContainsKey(UpperCase(mUser)) then
        begin
          Result.Add(UpperCase(mUser), mCurrent);
          mQueue.Enqueue(mUser);
        end;
      end;
    end;
  finally
    mQueue.Free;
  end;
end;

/// <summary>Kette "uA → uB → Haupt" ab AUser (Großschreibung).</summary>
function ChainOf(ANames, ANext: TDictionary<string, string>; const AUser: string): string;
var
  mStep, mNextStep: string;
begin
  if not ANames.TryGetValue(AUser, Result) then
  begin
    Result := AUser;
  end;
  if not ANext.TryGetValue(AUser, mStep) then
  begin
    mStep := '';
  end;
  while mStep <> '' do
  begin
    Result := Result + ' → ' + mStep;
    if not ANext.TryGetValue(UpperCase(mStep), mNextStep) then
    begin
      mNextStep := '';
    end;
    mStep := mNextStep;
  end;
end;

class function TCompletionUses.Cycles(const AUnits: TArray<TUnitIndex>; const AOwnUnit: string;
  const ANamespaces: TArray<string>): TDictionary<string, string>;
var
  mNames, mNext: TDictionary<string, string>;
  mUsers: TObjectDictionary<string, TList<string>>;
  mUser: string;
begin
  Result := TDictionary<string, string>.Create;
  if AOwnUnit = '' then
  begin
    Exit;
  end;
  mNames := ProjectNames(AUnits, AOwnUnit);
  mUsers := nil;
  mNext := nil;
  try
    mUsers := InterfaceUsers(AUnits, AOwnUnit, mNames, ANamespaces);
    mNext := ReachFrom(mUsers, AOwnUnit);
    for mUser in mNext.Keys do
    begin
      if not SameText(mUser, AOwnUnit) then
      begin
        Result.Add(mUser, ChainOf(mNames, mNext, mUser));
      end;
    end;
  finally
    mNext.Free;
    mUsers.Free;
    mNames.Free;
  end;
end;

class function TCompletionUses.Hidden(const ASite: TUsesSite; const APrefix: string;
  const ANamespaces: TArray<string>; AMatching: TCompletionMatching): TArray<string>;
var
  Name: string;
  Found: TUsesMatch;
begin
  Result := nil;
  if APrefix <> '' then
  begin
    for Name in ASite.Here do
    begin
      if Match(Name, APrefix, ANamespaces, AMatching, Found) then
      begin
        Result := Result + [Name];
      end;
    end;
  end;
  if Result = nil then
  begin
    Result := ASite.Here;
  end;
end;

type
  /// <summary>Gemeinsames für die Einträge von TCompletionUses.Collect.</summary>
  TUsesItems = record
    Request: TCompletionRequest;
    Prefix: string;
    Site: TUsesSite;
    Namespaces, HiddenUnits: TArray<string>;
    Own: string;
    // Zirkelbezüge im interface-Teil; sonst nil.
    Cycles: TDictionary<string, string>;
    // Ersetzt wird der ganze getippte Name samt Punkten, auch der Rest hinter dem Cursor.
    Range: TTextRange;
    /// <summary>Soll AUnitInfo erscheinen (nicht die eigene, nicht schon hier, passend)?</summary>
    function Wanted(const AUnitInfo: TUnitIndex; out AFound: TUsesMatch): Boolean;
    function Item(const AUnitInfo: TUnitIndex; const AFound: TUsesMatch; AGroup: TUsesGroup): TCompletionItem;
    /// <summary>Hinweis „bereits im … -Teil“, wenn der andere Abschnitt AUnitName einbindet.</summary>
    function Elsewhere(const AUnitName: string): string;
  end;

function TUsesItems.Wanted(const AUnitInfo: TUnitIndex; out AFound: TUsesMatch): Boolean;
begin
  Result := not SameText(AUnitInfo.UnitName, Own) and not TUsesClauses.IsUsed(Site.Here, AUnitInfo.UnitName,
    Namespaces) and TCompletionUses.Match(AUnitInfo.UnitName, Prefix, Namespaces, Request.Matching, AFound);
end;

function TUsesItems.Elsewhere(const AUnitName: string): string;
begin
  Result := '';
  if not TUsesClauses.IsUsed(Site.Other, AUnitName, Namespaces) then
  begin
    Exit;
  end;
  Result := TCompletionUses.SectionNames[TUsesSection.Interface_];
  if Site.Section = TUsesSection.Interface_ then
  begin
    Result := TCompletionUses.SectionNames[TUsesSection.Implementation_];
  end;
end;

function TUsesItems.Item(const AUnitInfo: TUnitIndex; const AFound: TUsesMatch;
  AGroup: TUsesGroup): TCompletionItem;
var
  mChain: string;
  mCount: Integer;
begin
  Result := Default(TCompletionItem);
  Result.Name := AUnitInfo.UnitName;
  Result.Kind := KindModule;
  Result.Detail := TCompletionUses.ShortPath(AUnitInfo.FileName);
  Result.HasTextEdit := True;
  Result.TextEdit := TTextEdit.Create(Range, AUnitInfo.UnitName);
  if (Request.Matching = TCompletionMatching.Fuzzy) and not AUnitInfo.UnitName.StartsWith(Prefix, True) then
  begin
    Result.FilterText := Prefix;
  end;
  Result.UsesGroup := TCompletionUses.GroupNames[AGroup];
  Result.UsesFilter := AFound.Filter;
  Result.UsesElsewhere := Elsewhere(AUnitInfo.UnitName);
  if (Cycles <> nil) and Cycles.TryGetValue(UpperCase(AUnitInfo.UnitName), mChain) then
  begin
    Result.UsesCycle := mChain;
  end;
  Result.UsesTypes := TCompletionUses.ExportedTypes(AUnitInfo, TCompletionUses.MaxTypes, mCount);
  Result.UsesTypeCount := mCount;
  Result.UsesHidden := HiddenUnits;
end;

/// <summary>Bereich des ganzen getippten Namens samt Punkten, auch des Rests hinter dem Cursor.</summary>
function NameRange(ARequest: TCompletionRequest; const APrefix: string): TTextRange;
var
  mLine: string;
  mStop: Integer;
begin
  mLine := ARequest.LineText(ARequest.Position.Line);
  mStop := ARequest.Position.Character;
  while (mStop < Length(mLine)) and (CharInSet(mLine[mStop + 1], ['A'..'Z', 'a'..'z', '0'..'9', '_', '.']) or
    (Ord(mLine[mStop + 1]) > 127)) do
  begin
    Inc(mStop);
  end;
  Result := TTextRange.Create(ARequest.Position.Line, Max(0, ARequest.Position.Character - Length(APrefix)),
    ARequest.Position.Line, mStop);
end;

/// <summary>Units des Index nach Namen sortiert.</summary>
function SortedUnits(const AIndex: ISymbolIndex): TArray<TUnitIndex>;
begin
  Result := AIndex.Units;
  TArray.Sort<TUnitIndex>(Result, TComparer<TUnitIndex>.Construct(
    function(const ALeft, ARight: TUnitIndex): Integer
    begin
      Result := CompareText(ALeft.UnitName, ARight.UnitName);
    end));
end;

/// <summary>Ausgangswerte für die Einträge: Namespaces, eigene Unit, Liste am Cursor, Fußzeile, Bereich.</summary>
function UsesItemsFor(ARequest: TCompletionRequest; const AContext: TCompletionContext): TUsesItems;
begin
  Result := Default(TUsesItems);
  Result.Request := ARequest;
  Result.Prefix := AContext.Prefix;
  if ARequest.Resolver <> nil then
  begin
    Result.Namespaces := ARequest.Resolver.Namespaces;
  end;
  if ARequest.Tree <> nil then
  begin
    Result.Own := TUsesClauses.OwnName(ARequest.Tree.Tokens);
    Result.Site := TCompletionUses.SiteAt(ARequest.Tree.Tokens, ARequest.Position);
  end;
  Result.HiddenUnits := TCompletionUses.Hidden(Result.Site, AContext.Prefix, Result.Namespaces,
    ARequest.Matching);
  Result.Range := NameRange(ARequest, AContext.Prefix);
end;

class procedure TCompletionUses.Collect(ARequest: TCompletionRequest; const AContext: TCompletionContext;
  ACollector: TCompletionCollector);
var
  mItems: TUsesItems;
  mUnits: TArray<TUnitIndex>;
  mUnitInfo: TUnitIndex;
  mFound: TUsesMatch;
  mGroup: TUsesGroup;
begin
  if ARequest.Index = nil then
  begin
    Exit;
  end;
  mItems := UsesItemsFor(ARequest, AContext);
  mUnits := SortedUnits(ARequest.Index);
  if mItems.Site.Section = TUsesSection.Interface_ then
  begin
    mItems.Cycles := Cycles(mUnits, mItems.Own, mItems.Namespaces);
  end;
  try
    for mUnitInfo in mUnits do
    begin
      if mItems.Wanted(mUnitInfo, mFound) then
      begin
        mGroup := GroupOf(mUnitInfo);
        ACollector.AddItem(mItems.Item(mUnitInfo, mFound, mGroup), mFound.Score - Ord(mGroup) * GroupPenalty);
      end;
    end;
  finally
    mItems.Cycles.Free;
  end;
end;

end.
