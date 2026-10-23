unit Atlas.Common.Rules.Builtin.PublicMembers;

// Regel unused-public-member (#1102, Gruppe „Stil und Metriken“): eine
// public- oder published-Methode, -Konstante oder -Property (auf Wunsch auch
// protected und Felder) bzw. eine Routine oder Konstante aus dem
// interface-Teil, die in der ganzen Projektgruppe nirgends verwendet wird.
// Erweitert unused-private-member (#1020) über die Grenze der Unit.
//
// Ablauf je Kandidat:
// - Ausnahmen über den Dienst „gilt als verwendet“ (Rules.ConsideredUsed).
// - Dateien im Suchbereich (Projekt bzw. Projektgruppe, IRuleProjectFiles):
//   Nur Dateien, in denen der Name als Bezeichner vorkommt (Verwendungen im
//   Index, #492), werden geparst; jedes Vorkommen außer Deklarationen und dem
//   eigenen Rumpf wird über die Namensauflösung geprüft. Löst es nicht sicher
//   auf, zählt es als Verwendung.
// - Formulardateien (Ereignis-Handler, Properties) und, mit
//   stringLiteralsCountAsUse, String-Literale mit genau dem Namen (RTTI).
// - published-Mitglieder gelten als verwendet, solange eine Formulardatei des
//   Suchbereichs nicht lesbar ist, und für Klassen, die eine Datei des
//   Suchbereichs in RegisterComponents, RegisterClass oder RegisterClasses
//   nennt (Streaming und Objektinspektor erreichen sie über RTTI).
// - Verwendungen nur in Testprojekten zählen mit testsCountAsUse = false nicht;
//   die Meldung nennt dann das Testprojekt.
//
// Die Regel schweigt, solange die Projekte nicht vollständig indiziert sind,
// eine Datei mit dem Namen nicht lesbar ist, die Unit Include-Dateien einbindet
// oder ein Projekt der Unit eine Art hat, die nicht in projectKinds steht
// (Vorgabe: nur Anwendungen; Packages und DLLs haben Nutzer außerhalb der
// Gruppe).

interface

uses
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

const
  UnusedPublicMemberRuleId = 'unused-public-member';

type
  TUnusedPublicMemberRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

procedure RegisterPublicMemberRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Pascal.DirectiveNames,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Dfm.FormModel,
  Atlas.Common.Rules.Derived,
  Atlas.Common.Rules.Options,
  Atlas.Common.Rules.ConsideredUsed,
  Atlas.Text.Lines;

const
  /// <summary>Aufrufe, die Klassen für Streaming und Objektinspektor bekannt machen.</summary>
  RegisterCalls: array[0..2] of string = ('RegisterComponents', 'RegisterClass', 'RegisterClasses');

type
{$SCOPEDENUMS ON}
  TUsage = (Used, Unused, OnlyTests);
{$SCOPEDENUMS OFF}

  /// <summary>Eine Datei im Suchbereich.</summary>
  TSearchFile = record
    FileName: string;
    /// <summary>Gehört nur zu Testprojekten.</summary>
    OnlyTests: Boolean;
    /// <summary>Name des ersten Testprojekts für die Meldung.</summary>
    TestProject: string;
  end;

/// <summary>"Öffentliche Methode", "Published-Property", "Geschütztes Feld" …</summary>
function KindText(const ASymbol: TIndexSymbol): string;
var
  Noun: string;
  Neuter: Boolean;
begin
  Neuter := ASymbol.Kind = TIndexSymbolKind.Field;
  case ASymbol.Kind of
    TIndexSymbolKind.Field:
      Noun := 'Feld';
    TIndexSymbolKind.Constant:
      Noun := 'Konstante';
    TIndexSymbolKind.Property_:
      Noun := 'Property';
    TIndexSymbolKind.Variable:
      Noun := 'Klassenvariable';
    TIndexSymbolKind.Routine:
      Noun := 'Routine';
  else
    Noun := 'Methode';
  end;
  case ASymbol.Visibility of
    TIndexVisibility.Published:
      Result := 'Published-' + Noun;
    TIndexVisibility.Protected, TIndexVisibility.StrictProtected:
      if Neuter then
        Result := 'Geschütztes ' + Noun
      else
        Result := 'Geschützte ' + Noun;
  else
    if Neuter then
      Result := 'Öffentliches ' + Noun
    else
      Result := 'Öffentliche ' + Noun;
  end;
end;

function VisibilityKey(AVisibility: TIndexVisibility): string;
begin
  case AVisibility of
    TIndexVisibility.Published:
      Result := 'published';
    TIndexVisibility.Protected, TIndexVisibility.StrictProtected:
      Result := 'protected';
    TIndexVisibility.Public:
      Result := 'public';
  else
    Result := '';
  end;
end;

function MemberKindKey(const ASymbol: TIndexSymbol): string;
begin
  case ASymbol.Kind of
    TIndexSymbolKind.Method, TIndexSymbolKind.Routine:
      Result := 'method';
    TIndexSymbolKind.Constant:
      Result := 'constant';
    TIndexSymbolKind.Property_:
      Result := 'property';
    TIndexSymbolKind.Field:
      Result := 'field';
    TIndexSymbolKind.Variable:
      Result := 'classVar';
  else
    Result := '';
  end;
end;

function ProjectKindKey(AKind: TRuleProjectKind): string;
begin
  case AKind of
    TRuleProjectKind.Application:
      Result := 'application';
    TRuleProjectKind.Package:
      Result := 'package';
    TRuleProjectKind.Library_:
      Result := 'library';
  else
    Result := '';
  end;
end;

function QualifiedOf(const ASymbol: TIndexSymbol): string;
begin
  if ASymbol.Container <> '' then
    Result := ASymbol.Container + '.' + ASymbol.Name
  else
    Result := ASymbol.Name;
end;

function CleanName(const AText: string): string;
begin
  if StartsStr('&', AText) then
    Result := Copy(AText, 2, MaxInt)
  else
    Result := AText;
end;

function SamePosition(const A, B: TTextPosition): Boolean;
begin
  Result := (A.Line = B.Line) and (A.Character = B.Character);
end;

function Contains(const AItems: TArray<string>; const AItem: string): Boolean;
begin
  Result := IndexText(AItem, AItems) >= 0;
end;

{ TUnusedPublicMemberRule }

function TUnusedPublicMemberRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(UnusedPublicMemberRuleId, TRuleSeverity.Hint,
    'Öffentliches Mitglied wird im Projekt nie verwendet');
end;

procedure TUnusedPublicMemberRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Cache: IRuleDerivedCache;
  Local: TUnitIndex;
  Tokens: TArray<TPascalToken>;
  Lines: TArray<string>;
  FileName, Reason, LineBreak: string;
  Visibilities, MemberKinds, ProjectKinds: TArray<string>;
  UnitLevel, WholeGroup, TestsCount, StringsCount: Boolean;
  Projects: TArray<TRuleProject>;
  Files: TList<TSearchFile>;
  Forms: TList<string>;
  Texts: TDictionary<string, string>;
  Resolver: TNameResolver;
  Considered: TConsideredUsed;
  // Klassen (Kurzname, klein) -> in RegisterComponents/RegisterClass(es) genannt; je Prüfung einmal.
  Registered: TDictionary<string, Boolean>;
  // 0 = noch nicht geprüft, 1 = alle Formulardateien lesbar, 2 = mindestens eine nicht.
  FormsState: Integer;

  function HasIncludes: Boolean;
  var
    Token: TPascalToken;
    Name: string;
  begin
    for Token in AContext.Tree.Tokens do
      if Token.Kind = TPascalTokenKind.Directive then
      begin
        Name := TDirectiveNames.LeadingName(TDirectiveNames.Body(Token.Text));
        if SameText(Name, 'I') or SameText(Name, 'INCLUDE') then
          Exit(True);
      end;
    Result := False;
  end;

  /// <summary>Gehören alle Projekte der Datei zu einer erlaubten Art?</summary>
  function KindsAllowed: Boolean;
  var
    Project: TRuleProject;
    Source: string;
  begin
    for Project in Projects do
      for Source in Project.Sources do
        if SameText(Source, FileName) and not Contains(ProjectKinds, ProjectKindKey(Project.Kind)) then
          Exit(False);
    Result := True;
  end;

  procedure CollectFiles;
  var
    Project: TRuleProject;
    Source, Form: string;
    Seen: TDictionary<string, Integer>;
    Entry: TSearchFile;
    Position: Integer;
  begin
    Seen := TDictionary<string, Integer>.Create;
    try
      // Die eigene Datei zuerst: Dort steht die häufigste Verwendung.
      Entry := Default(TSearchFile);
      Entry.FileName := FileName;
      Files.Add(Entry);
      Seen.Add(UpperCase(FileName), 0);
      for Project in Projects do
      begin
        for Source in Project.Sources do
          if Seen.TryGetValue(UpperCase(Source), Position) then
          begin
            // Gehört die Datei auch zu einem Projekt, das kein Test ist, zählt sie normal.
            if not Project.IsTest then
            begin
              Entry := Files[Position];
              Entry.OnlyTests := False;
              Entry.TestProject := '';
              Files[Position] := Entry;
            end;
          end
          else
          begin
            Entry := Default(TSearchFile);
            Entry.FileName := Source;
            Entry.OnlyTests := Project.IsTest;
            if Project.IsTest then
              Entry.TestProject := ChangeFileExt(ExtractFileName(Project.FileName), '');
            Seen.Add(UpperCase(Source), Files.Count);
            Files.Add(Entry);
          end;
        for Form in Project.Forms do
          if not Forms.Contains(Form) then
            Forms.Add(Form);
      end;
    finally
      Seen.Free;
    end;
  end;

  function TextOf(const AFile: string; out AText: string): Boolean;
  begin
    if SameText(AFile, FileName) then
    begin
      AText := AContext.Text;
      Exit(True);
    end;
    if Texts.TryGetValue(UpperCase(AFile), AText) then
      Exit(True);
    Result := AContext.ProjectFiles.ReadText(AFile, AText);
    if Result then
      Texts.Add(UpperCase(AFile), AText);
  end;

  function IsTarget(const AResolved: TResolvedSymbol; const ASymbol: TIndexSymbol; AAmbiguous: Boolean): Boolean;
  begin
    Result := AResolved.Found and SameText(AResolved.Name, ASymbol.Name) and
      SameText(AResolved.Container, ASymbol.Container) and
      (SameText(AResolved.UnitName, Local.UnitName) or SameText(AResolved.FileName, FileName));
    // Bei eindeutig aufgelösten Überladungen zählt nur die passende.
    if Result and not AAmbiguous and (ASymbol.Kind in [TIndexSymbolKind.Method, TIndexSymbolKind.Routine]) and
      ASymbol.HasDirective('overload') and (AResolved.ParamTypes <> nil) then
      Result := AnsiSameText(string.Join(',', AResolved.ParamTypes), string.Join(',', ASymbol.ParamTypes));
  end;

  /// <summary>Deklarationen mit dem Namen in AFile: dort ist der Name keine Verwendung.</summary>
  function DeclaredAt(const AFile, AName: string): TArray<TTextPosition>;
  var
    Indexed: TUnitIndex;
    Symbol: TIndexSymbol;
    Position: Integer;
  begin
    Result := nil;
    if SameText(AFile, FileName) then
    begin
      for Position in Local.SymbolsNamed(AName) do
        Result := Result + [Local.Symbols[Position].SelectionRange.StartPos];
      Exit;
    end;
    if AContext.Index.FindFile(AFile, Indexed) then
      for Symbol in Indexed.Symbols do
        if SameText(Symbol.Name, AName) and (Symbol.FileName = '') then
          Result := Result + [Symbol.SelectionRange.StartPos];
  end;

  /// <summary>Rümpfe von ASymbol in der eigenen Datei (Rekursion ist keine Verwendung).</summary>
  function OwnBodies(const ASymbol: TIndexSymbol): TArray<TSyntaxNode>;
  var
    Node: TSyntaxNode;
    Wanted: string;
  begin
    Result := nil;
    if ASymbol.Container <> '' then
      Wanted := ASymbol.Container + '.' + ASymbol.Name
    else
      Wanted := ASymbol.Name;
    for Node in TRuleDerived.Routines(Cache, AContext) do
      if SameText(Node.Name, Wanted) then
        Result := Result + [Node];
  end;

  function Inside(const APosition: TTextPosition; const ANodes: TArray<TSyntaxNode>): Boolean;
  var
    Node: TSyntaxNode;
  begin
    for Node in ANodes do
      if ((APosition.Line > Node.StartPos.Line) or ((APosition.Line = Node.StartPos.Line) and
        (APosition.Character >= Node.StartPos.Character))) and ((APosition.Line < Node.EndPos.Line) or
        ((APosition.Line = Node.EndPos.Line) and (APosition.Character <= Node.EndPos.Character))) then
        Exit(True);
    Result := False;
  end;

  /// <summary>Verwendet ATree (Datei AFile) ASymbol? Nicht sicher auflösbare Vorkommen zählen als Verwendung.
  /// </summary>
  function UsedInTree(ATree: TSyntaxTree; const AFile: string; const ASymbol: TIndexSymbol): Boolean;
  var
    Declared: TArray<TTextPosition>;
    Bodies: TArray<TSyntaxNode>;
    Index: Integer;
    Position, Skip: TTextPosition;
    Excluded: Boolean;
    Results: TArray<TResolvedSymbol>;
    Resolved: TResolvedSymbol;
  begin
    Result := False;
    Declared := DeclaredAt(AFile, ASymbol.Name);
    Bodies := nil;
    if SameText(AFile, FileName) then
      Bodies := OwnBodies(ASymbol);
    Resolver.PinTree(ATree, AFile);
    try
      for Index := 0 to High(ATree.Tokens) do
      begin
        if (ATree.Tokens[Index].Kind <> TPascalTokenKind.Identifier) or
          not SameText(CleanName(ATree.Tokens[Index].Text), ASymbol.Name) then
          Continue;
        Position := ATree.Tokens[Index].StartPos;
        Excluded := False;
        for Skip in Declared do
          if SamePosition(Skip, Position) then
            Excluded := True;
        if Excluded or Inside(Position, Bodies) then
          Continue;
        if Assigned(AContext.Cancelled) and AContext.Cancelled() then
          raise ERuleCheckCancelled.Create(UnusedPublicMemberRuleId);
        Results := Resolver.ResolveAll(ATree, AFile, Position);
        if (Results = nil) or not Results[0].Found then
          Exit(True);
        for Resolved in Results do
          if IsTarget(Resolved, ASymbol, Length(Results) > 1) then
            Exit(True);
      end;
    finally
      Resolver.UnpinTree;
    end;
  end;

  function InForms(const AName: string): Boolean;
  var
    Form, Text: string;
    Model: TFormModel;
  begin
    for Form in Forms do
    begin
      if not TextOf(Form, Text) or not ContainsText(Text, AName) then
        Continue;
      Model := TFormModel.Create(Text);
      try
        if Model.Occurrences(AName) <> nil then
          Exit(True);
      finally
        Model.Free;
      end;
    end;
    Result := False;
  end;

  /// <summary>Ist eine Formulardatei des Suchbereichs nicht lesbar? Dann können published-Methoden dort als
  /// Handler stehen.</summary>
  function FormUnreadable: Boolean;
  var
    Form, Text: string;
  begin
    if FormsState = 0 then
    begin
      FormsState := 1;
      for Form in Forms do
        if not TextOf(Form, Text) then
          FormsState := 2;
    end;
    Result := FormsState = 2;
  end;

  /// <summary>Nennt ein Aufruf RegisterComponents, RegisterClass oder RegisterClasses in ATokens die Klasse
  /// AClass?</summary>
  function RegistersIn(const ATokens: TArray<TPascalToken>; const AClass: string): Boolean;
  var
    Index, At, Depth: Integer;
  begin
    for Index := 0 to High(ATokens) - 1 do
      if (ATokens[Index].Kind = TPascalTokenKind.Identifier) and (IndexText(CleanName(ATokens[Index].Text),
        RegisterCalls) >= 0) and ATokens[Index + 1].IsSymbol('(') then
      begin
        // Argumente bis zur schließenden Klammer: RegisterComponents('Seite', [TA, TB]), RegisterClass(TA).
        Depth := 0;
        At := Index + 1;
        while At <= High(ATokens) do
        begin
          if ATokens[At].IsSymbol('(') then
            Inc(Depth)
          else if ATokens[At].IsSymbol(')') then
          begin
            Dec(Depth);
            if Depth = 0 then
              Break;
          end
          else if (ATokens[At].Kind = TPascalTokenKind.Identifier) and SameText(CleanName(ATokens[At].Text), AClass) then
            Exit(True);
          Inc(At);
        end;
      end;
    Result := False;
  end;

  /// <summary>Registriert eine Datei des Suchbereichs die Klasse AContainer (RegisterComponents,
  /// RegisterClass, RegisterClasses)? Nicht lesbare Dateien mit einem dieser Aufrufe zählen als ja.</summary>
  function IsRegistered(const AContainer: string): Boolean;
  var
    Short, Call, Text: string;
    Entry: TSearchFile;
    Mentioned: Boolean;
    Tree: TSyntaxTree;
  begin
    Short := Copy(AContainer, LastDelimiter('.', AContainer) + 1, MaxInt);
    if Registered.TryGetValue(LowerCase(Short), Result) then
      Exit;
    Result := False;
    for Entry in Files do
    begin
      if SameText(Entry.FileName, FileName) then
        Result := RegistersIn(AContext.Tree.Tokens, Short)
      else
      begin
        Mentioned := False;
        for Call in RegisterCalls do
          case AContext.ProjectFiles.NameIn(Entry.FileName, Call) of
            TRuleNameAnswer.Present:
              Mentioned := True;
            TRuleNameAnswer.Unknown:
              Result := True;
          end;
        if Mentioned and not Result then
        begin
          if not TextOf(Entry.FileName, Text) then
            Result := True
          else
          begin
            Tree := TSyntaxTreeCache.Parse(Text);
            try
              Result := RegistersIn(Tree.Tokens, Short);
            finally
              Tree.Free;
            end;
          end;
        end;
      end;
      if Result then
        Break;
    end;
    Registered.Add(LowerCase(Short), Result);
  end;

  /// <summary>Kommt AName als String-Literal ('Name') in einer Datei des Suchbereichs vor?</summary>
  function InStrings(const AName: string): Boolean;
  var
    Entry: TSearchFile;
    Text: string;
    Tree: TSyntaxTree;
    Found: TArray<TPascalToken>;
    Token: TPascalToken;
  begin
    for Entry in Files do
    begin
      if not TextOf(Entry.FileName, Text) or not ContainsText(Text, '''' + AName + '''') then
        Continue;
      Tree := nil;
      try
        if SameText(Entry.FileName, FileName) then
          Found := AContext.Tree.Tokens
        else
        begin
          Tree := TSyntaxTreeCache.Parse(Text);
          Found := Tree.Tokens;
        end;
        for Token in Found do
          if (Token.Kind = TPascalTokenKind.StringLiteral) and SameText(Token.Text, '''' + AName + '''') then
            Exit(True);
      finally
        Tree.Free;
      end;
    end;
    Result := False;
  end;

  /// <summary>Wo wird ASymbol verwendet? ATestProject: das Testprojekt bei OnlyTests. Was nicht sicher zu
  /// beantworten ist, gilt als Used.</summary>
  function UsageOf(const ASymbol: TIndexSymbol; out ATestProject: string): TUsage;
  var
    Entry: TSearchFile;
    Text: string;
    Tree: TSyntaxTree;
    Used: Boolean;
  begin
    ATestProject := '';
    Result := TUsage.Unused;
    for Entry in Files do
    begin
      if SameText(Entry.FileName, FileName) then
        Used := UsedInTree(AContext.Tree, FileName, ASymbol)
      else
      begin
        case AContext.ProjectFiles.NameIn(Entry.FileName, ASymbol.Name) of
          TRuleNameAnswer.Absent:
            Continue;
          TRuleNameAnswer.Unknown:
            Exit(TUsage.Used);
        end;
        if not TextOf(Entry.FileName, Text) then
          Exit(TUsage.Used);
        Tree := TSyntaxTreeCache.Parse(Text);
        try
          Used := UsedInTree(Tree, Entry.FileName, ASymbol);
        finally
          Tree.Free;
        end;
      end;
      if not Used then
        Continue;
      if Entry.OnlyTests and not TestsCount then
      begin
        if ATestProject = '' then
          ATestProject := Entry.TestProject;
        Result := TUsage.OnlyTests;
        Continue;
      end;
      Exit(TUsage.Used);
    end;
    if InForms(ASymbol.Name) or (StringsCount and InStrings(ASymbol.Name)) then
      Exit(TUsage.Used);
  end;

  function IgnoreFix(const ASymbol: TIndexSymbol): TRuleFix;
  var
    Line: Integer;
    Indent: string;
  begin
    Line := ASymbol.Range.StartPos.Line;
    Indent := '';
    if Line < Length(Lines) then
      Indent := Copy(Lines[Line], 1, Length(Lines[Line]) - Length(TrimLeft(Lines[Line])));
    Result := TRuleFix.Create('Als bewusst öffentlich markieren (lsp-ignore)',
      [TTextEdit.Create(TTextRange.Create(Line, 0, Line, 0), Indent + '// lsp-ignore: ' +
      UnusedPublicMemberRuleId + LineBreak)]);
    Result.Alternative := True;
  end;

  function Wanted(const ASymbol: TIndexSymbol): Boolean;
  begin
    if ASymbol.Unavailable or (ASymbol.FileName <> '') or not Contains(MemberKinds, MemberKindKey(ASymbol)) then
      Exit(False);
    if ASymbol.Container = '' then
      Exit(UnitLevel and ASymbol.InInterface and (ASymbol.Kind in [TIndexSymbolKind.Routine,
        TIndexSymbolKind.Constant]));
    Result := (ASymbol.Kind in [TIndexSymbolKind.Method, TIndexSymbolKind.Constant, TIndexSymbolKind.Property_,
      TIndexSymbolKind.Field, TIndexSymbolKind.Variable]) and Contains(Visibilities, VisibilityKey(ASymbol.Visibility));
  end;

  /// <summary>Durchsuchter Bereich für den Befund-Hover: "Durchsucht: 214 Units und 37 Formulare der
  /// Projektgruppe".</summary>
  function SearchedText: string;

    function Counted(ACount: Integer; const AOne, AMany: string): string;
    begin
      if ACount = 1 then
        Result := '1 ' + AOne
      else
        Result := Format('%d %s', [ACount, AMany]);
    end;

  begin
    Result := 'Durchsucht: ' + Counted(Files.Count, 'Datei', 'Dateien');
    if Forms.Count > 0 then
      Result := Result + ' und ' + Counted(Forms.Count, 'Formular', 'Formulare');
    if WholeGroup then
      Result := Result + ' der Projektgruppe'
    else
      Result := Result + ' des Projekts';
  end;

  procedure CheckSymbol(const ASymbol: TIndexSymbol);
  var
    TestProject: string;
  begin
    if Considered.Reason(ASymbol) <> TConsideredUsedReason.None then
      Exit;
    if (ASymbol.Visibility = TIndexVisibility.Published) and (ASymbol.Container <> '') and
      (((ASymbol.Kind = TIndexSymbolKind.Method) and FormUnreadable) or IsRegistered(ASymbol.Container)) then
      Exit;
    case UsageOf(ASymbol, TestProject) of
      TUsage.Unused:
        AReport.AddWithDetails(ASymbol.SelectionRange, Format('%s %s wird im Projekt nirgends verwendet.',
          [KindText(ASymbol), QualifiedOf(ASymbol)]), SearchedText, TRuleConfidence.Medium, [IgnoreFix(ASymbol)]);
      TUsage.OnlyTests:
        AReport.AddWithDetails(ASymbol.SelectionRange, Format('%s %s wird nur in %s verwendet.',
          [KindText(ASymbol), QualifiedOf(ASymbol), TestProject]), SearchedText, TRuleConfidence.Medium,
          [IgnoreFix(ASymbol)]);
    end;
  end;

var
  Symbol: TIndexSymbol;
  Seen: TDictionary<string, Boolean>;
  Key: string;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) or (AContext.ProjectFiles = nil) or
    (AContext.Index = nil) or (AContext.FileName = '') or HasIncludes then
    Exit;
  FileName := AContext.FileName;
  Visibilities := TRuleOptions.Strings(AContext.Options, 'visibilities', ['public', 'published']);
  MemberKinds := TRuleOptions.Strings(AContext.Options, 'memberKinds', ['method', 'constant', 'property']);
  ProjectKinds := TRuleOptions.Strings(AContext.Options, 'projectKinds', ['application']);
  UnitLevel := TRuleOptions.Bool(AContext.Options, 'unitLevel', True);
  WholeGroup := not SameText(TRuleOptions.Text(AContext.Options, 'scope', 'projectGroup'), 'project');
  TestsCount := TRuleOptions.Bool(AContext.Options, 'testsCountAsUse', True);
  StringsCount := TRuleOptions.Bool(AContext.Options, 'stringLiteralsCountAsUse', True);
  Projects := AContext.ProjectFiles.ProjectsOf(FileName, WholeGroup);
  if (Projects = nil) or not KindsAllowed or not AContext.ProjectFiles.Complete(Reason) then
    Exit;
  Cache := TRuleDerived.Open(AContext);
  Local := TRuleDerived.UnitIndex(Cache, AContext);
  Tokens := TRuleDerived.CodeTokens(Cache, AContext);
  Lines := TTextLines.SplitLines(AContext.Text, LineBreak);
  if LineBreak = '' then
    LineBreak := sLineBreak;
  Files := TList<TSearchFile>.Create;
  Forms := TList<string>.Create;
  Texts := TDictionary<string, string>.Create;
  Registered := TDictionary<string, Boolean>.Create;
  FormsState := 0;
  Seen := TDictionary<string, Boolean>.Create;
  Considered := TConsideredUsed.Create(AContext.Index, Local, Tokens,
    TRuleOptions.Strings(AContext.Options, 'keepAttributes', []),
    TRuleOptions.Strings(AContext.Options, 'keepPatterns', []));
  Resolver := TNameResolver.Create(AContext.Index, AContext.EnsureUnit);
  try
    Resolver.Namespaces := AContext.Namespaces;
    CollectFiles;
    for Symbol in Local.Symbols do
    begin
      if Symbol.Unavailable or (Symbol.FileName <> '') then
        Continue;
      // Nur die erste Deklaration (im Typ bzw. im interface-Teil) entscheidet, nicht der Rumpf; Überladungen
      // einzeln. Auch eine nicht gewünschte Deklaration (protected) zählt als gesehen, sonst prüfte die Regel den
      // Rumpf, der im Index als public steht.
      Key := LowerCase(Symbol.Container + '.' + Symbol.Name + '(' + string.Join(',', Symbol.ParamTypes) + ')');
      if Seen.ContainsKey(Key) then
        Continue;
      Seen.Add(Key, True);
      if Wanted(Symbol) then
        CheckSymbol(Symbol);
    end;
  finally
    Resolver.Free;
    Considered.Free;
    Seen.Free;
    Texts.Free;
    Registered.Free;
    Forms.Free;
    Files.Free;
  end;
end;

procedure RegisterPublicMemberRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TUnusedPublicMemberRule.Create);
end;

end.
