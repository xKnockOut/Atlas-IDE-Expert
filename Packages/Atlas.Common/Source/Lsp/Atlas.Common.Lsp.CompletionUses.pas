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
    if Result = '' then
      Result := AParts[Index]
    else
      Result := Result + '.' + AParts[Index];
end;

{ TCompletionUses }

class function TCompletionUses.GroupOf(const AUnit: TUnitIndex): TUsesGroup;
var
  Namespace, Path, Known: string;
begin
  if not AUnit.Library_ then
    Exit(TUsesGroup.Project);
  Path := LowerCase(AUnit.FileName.Replace('/', '\'));
  if Pos('\embarcadero\studio\', Path) > 0 then
    Exit(TUsesGroup.Rtl);
  Namespace := '';
  if Pos('.', AUnit.UnitName) > 0 then
    Namespace := Copy(AUnit.UnitName, 1, Pos('.', AUnit.UnitName) - 1);
  for Known in RtlNamespaces do
    if SameText(Namespace, Known) then
      Exit(TUsesGroup.Rtl);
  Result := TUsesGroup.Library_;
end;

class function TCompletionUses.SiteAt(const ATokens: TArray<TPascalToken>; const APosition: TTextPosition): TUsesSite;
var
  Index, First: Integer;
  IsUnit, InImplementation, Current, AtCursor, AfterIn: Boolean;
  Name: string;
  Interface_, Implementation_, Others, Names: TArray<string>;
  Section, ClauseSection: TUsesSection;
  Token: TPascalToken;

  procedure Flush;
  begin
    if (Name <> '') and not Current then
      Names := Names + [Name];
    Name := '';
    Current := False;
    AfterIn := False;
  end;

begin
  Result := Default(TUsesSite);
  Interface_ := nil;
  Implementation_ := nil;
  Others := nil;
  Section := TUsesSection.Other;
  First := 0;
  while (First <= High(ATokens)) and IsTrivia(ATokens[First]) do
    Inc(First);
  IsUnit := (First <= High(ATokens)) and ATokens[First].IsKeyword('unit');
  InImplementation := False;
  Index := 0;
  while Index <= High(ATokens) do
  begin
    Token := ATokens[Index];
    if Token.IsKeyword('implementation') then
      InImplementation := True
    else if Token.IsKeyword('uses') or Token.IsKeyword('contains') then
    begin
      ClauseSection := TUsesSection.Other;
      if IsUnit and InImplementation then
        ClauseSection := TUsesSection.Implementation_
      else if IsUnit then
        ClauseSection := TUsesSection.Interface_;
      AtCursor := not Before(APosition, Token.EndPos);
      Names := nil;
      Name := '';
      Current := False;
      AfterIn := False;
      Inc(Index);
      while Index <= High(ATokens) do
      begin
        Token := ATokens[Index];
        if IsTrivia(Token) then
        begin
          Inc(Index);
          Continue;
        end;
        if Token.IsSymbol(',') then
          Flush
        else if Token.IsSymbol(';') or (Token.Kind = TPascalTokenKind.Keyword) and not Token.IsKeyword('in') then
          Break
        else if Token.IsKeyword('in') then
          AfterIn := True
        else if not AfterIn and ((Token.Kind = TPascalTokenKind.Identifier) or Token.IsSymbol('.')) then
        begin
          Name := Name + Token.Text;
          // Der Name, an dem getippt wird, zählt nicht als eingebunden.
          if Before(Token.StartPos, APosition) and not Before(Token.EndPos, APosition) then
            Current := True;
        end;
        Inc(Index);
      end;
      Flush;
      // Cursor in dieser Liste: hinter "uses" und vor dem Ende (Semikolon bzw. erstes fremdes Token).
      if AtCursor and ((Index > High(ATokens)) or not Before(ATokens[Index].StartPos, APosition)) then
        Section := ClauseSection;
      case ClauseSection of
        TUsesSection.Interface_:
          Interface_ := Interface_ + Names;
        TUsesSection.Implementation_:
          Implementation_ := Implementation_ + Names;
      else
        Others := Others + Names;
      end;
      Continue;
    end;
    Inc(Index);
  end;
  Result.Section := Section;
  case Section of
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

class function TCompletionUses.Match(const AUnitName, APrefix: string; const ANamespaces: TArray<string>;
  AMatching: TCompletionMatching; out AMatch: TUsesMatch): Boolean;
var
  Parts: TArray<string>;
  Part, Dots, Score, Penalty: Integer;
  Lead, Namespace: string;
begin
  AMatch := Default(TUsesMatch);
  AMatch.Score := TFuzzyMatch.NoMatch;
  Parts := AUnitName.Split(['.']);
  Dots := Length(APrefix) - Length(APrefix.Replace('.', ''));
  Result := False;
  for Part := 0 to High(Parts) do
  begin
    // Ohne Eingabe nur der volle Name; sonst jede Stelle, an der ein Namensteil beginnt.
    if (APrefix = '') and (Part > 0) then
      Break;
    Score := MatchScore(JoinParts(Parts, Part), APrefix, AMatching);
    if Score = TFuzzyMatch.NoMatch then
      Continue;
    Penalty := 0;
    if Part > 0 then
    begin
      Penalty := PartPenalty;
      Lead := JoinParts(Copy(Parts, 0, Part), 0);
      for Namespace in ANamespaces do
        if SameText(Namespace, Lead) then
          Penalty := NamespacePenalty;
    end;
    Dec(Score, Penalty);
    if Result and (Score <= AMatch.Score) then
      Continue;
    Result := True;
    AMatch.Score := Score;
    AMatch.Filter := JoinParts(Parts, Min(Part + Dots, High(Parts)));
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
    Exit;
  // Hinter "Studio\" steht die Version ("37.0"), dann der Rest unter $(BDS).
  Stop := PosEx('\', Path, Start + Length(Marker));
  if Stop = 0 then
    Exit;
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
      Continue;
    Inc(ACount);
    if Length(Result) >= AMax then
      Continue;
    Name := Symbol.Name;
    if Symbol.TypeParams <> '' then
      Name := Name + '<' + Symbol.TypeParams.Replace(' ', '') + '>';
    Result := Result + [Name];
  end;
end;

class function TCompletionUses.Cycles(const AUnits: TArray<TUnitIndex>; const AOwnUnit: string;
  const ANamespaces: TArray<string>): TDictionary<string, string>;
var
  Names: TDictionary<string, string>;
  Users: TObjectDictionary<string, TList<string>>;
  Next: TDictionary<string, string>;
  Queue: TQueue<string>;
  UnitInfo: TUnitIndex;
  Used, Target, Current, User, Chain, Step: string;
  List: TList<string>;

  function Resolve(const AName: string): string;
  var
    Namespace: string;
  begin
    if Names.TryGetValue(UpperCase(AName), Result) then
      Exit;
    for Namespace in ANamespaces do
      if Names.TryGetValue(UpperCase(Namespace + '.' + AName), Result) then
        Exit;
    Result := '';
  end;

begin
  Result := TDictionary<string, string>.Create;
  if AOwnUnit = '' then
    Exit;
  Names := TDictionary<string, string>.Create;
  Users := TObjectDictionary<string, TList<string>>.Create([doOwnsValues]);
  Next := TDictionary<string, string>.Create;
  Queue := TQueue<string>.Create;
  try
    // Nur Projekt-Units: Bibliotheken binden keine Projekt-Units ein.
    for UnitInfo in AUnits do
      if not UnitInfo.Library_ then
        Names.AddOrSetValue(UpperCase(UnitInfo.UnitName), UnitInfo.UnitName);
    Names.AddOrSetValue(UpperCase(AOwnUnit), AOwnUnit);
    // Rückwärts: wer bindet wen im interface-Teil ein.
    for UnitInfo in AUnits do
    begin
      if UnitInfo.Library_ or SameText(UnitInfo.UnitName, AOwnUnit) then
        Continue;
      for Used in UnitInfo.InterfaceUses do
      begin
        Target := Resolve(Used);
        if Target = '' then
          Continue;
        if not Users.TryGetValue(UpperCase(Target), List) then
        begin
          List := TList<string>.Create;
          Users.Add(UpperCase(Target), List);
        end;
        List.Add(UnitInfo.UnitName);
      end;
    end;
    Queue.Enqueue(AOwnUnit);
    Next.Add(UpperCase(AOwnUnit), '');
    while Queue.Count > 0 do
    begin
      Current := Queue.Dequeue;
      if not Users.TryGetValue(UpperCase(Current), List) then
        Continue;
      for User in List do
        if not Next.ContainsKey(UpperCase(User)) then
        begin
          Next.Add(UpperCase(User), Current);
          Queue.Enqueue(User);
        end;
    end;
    for User in Next.Keys do
    begin
      if SameText(User, AOwnUnit) then
        Continue;
      Chain := Names[User];
      Step := Next[User];
      while Step <> '' do
      begin
        Chain := Chain + ' → ' + Step;
        Step := Next[UpperCase(Step)];
      end;
      Result.Add(User, Chain);
    end;
  finally
    Queue.Free;
    Next.Free;
    Users.Free;
    Names.Free;
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
    for Name in ASite.Here do
      if Match(Name, APrefix, ANamespaces, AMatching, Found) then
        Result := Result + [Name];
  if Result = nil then
    Result := ASite.Here;
end;

class procedure TCompletionUses.Collect(ARequest: TCompletionRequest; const AContext: TCompletionContext;
  ACollector: TCompletionCollector);
var
  Units: TArray<TUnitIndex>;
  UnitInfo: TUnitIndex;
  Site: TUsesSite;
  Namespaces, HiddenUnits: TArray<string>;
  Own, Line, Chain: string;
  Found: TUsesMatch;
  Item: TCompletionItem;
  Group: TUsesGroup;
  Cycles_: TDictionary<string, string>;
  Start, Stop, Count: Integer;
begin
  if ARequest.Index = nil then
    Exit;
  Namespaces := nil;
  if ARequest.Resolver <> nil then
    Namespaces := ARequest.Resolver.Namespaces;
  Own := '';
  Site := Default(TUsesSite);
  if ARequest.Tree <> nil then
  begin
    Own := TUsesClauses.OwnName(ARequest.Tree.Tokens);
    Site := SiteAt(ARequest.Tree.Tokens, ARequest.Position);
  end;
  HiddenUnits := Hidden(Site, AContext.Prefix, Namespaces, ARequest.Matching);
  // Ersetzt wird der ganze getippte Name samt Punkten, auch der Rest hinter dem Cursor.
  Line := ARequest.LineText(ARequest.Position.Line);
  Start := Max(0, ARequest.Position.Character - Length(AContext.Prefix));
  Stop := ARequest.Position.Character;
  while (Stop < Length(Line)) and (CharInSet(Line[Stop + 1], ['A'..'Z', 'a'..'z', '0'..'9', '_', '.']) or
    (Ord(Line[Stop + 1]) > 127)) do
    Inc(Stop);
  Units := ARequest.Index.Units;
  TArray.Sort<TUnitIndex>(Units, TComparer<TUnitIndex>.Construct(
    function(const ALeft, ARight: TUnitIndex): Integer
    begin
      Result := CompareText(ALeft.UnitName, ARight.UnitName);
    end));
  Cycles_ := nil;
  if Site.Section = TUsesSection.Interface_ then
    Cycles_ := Cycles(Units, Own, Namespaces);
  try
    for UnitInfo in Units do
    begin
      if SameText(UnitInfo.UnitName, Own) or TUsesClauses.IsUsed(Site.Here, UnitInfo.UnitName, Namespaces) or
        not Match(UnitInfo.UnitName, AContext.Prefix, Namespaces, ARequest.Matching, Found) then
        Continue;
      Group := GroupOf(UnitInfo);
      Item := Default(TCompletionItem);
      Item.Name := UnitInfo.UnitName;
      Item.Kind := KindModule;
      Item.Detail := ShortPath(UnitInfo.FileName);
      Item.HasTextEdit := True;
      Item.TextEdit := TTextEdit.Create(TTextRange.Create(ARequest.Position.Line, Start, ARequest.Position.Line,
        Stop), UnitInfo.UnitName);
      if (ARequest.Matching = TCompletionMatching.Fuzzy) and
        not UnitInfo.UnitName.StartsWith(AContext.Prefix, True) then
        Item.FilterText := AContext.Prefix;
      Item.UsesGroup := GroupNames[Group];
      Item.UsesFilter := Found.Filter;
      if TUsesClauses.IsUsed(Site.Other, UnitInfo.UnitName, Namespaces) then
        if Site.Section = TUsesSection.Interface_ then
          Item.UsesElsewhere := SectionNames[TUsesSection.Implementation_]
        else
          Item.UsesElsewhere := SectionNames[TUsesSection.Interface_];
      if (Cycles_ <> nil) and Cycles_.TryGetValue(UpperCase(UnitInfo.UnitName), Chain) then
        Item.UsesCycle := Chain;
      Item.UsesTypes := ExportedTypes(UnitInfo, MaxTypes, Count);
      Item.UsesTypeCount := Count;
      Item.UsesHidden := HiddenUnits;
      ACollector.AddItem(Item, Found.Score - Ord(Group) * GroupPenalty);
    end;
  finally
    Cycles_.Free;
  end;
end;

end.
