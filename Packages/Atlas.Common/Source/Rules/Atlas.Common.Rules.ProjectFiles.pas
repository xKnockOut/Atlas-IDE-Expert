unit Atlas.Common.Rules.ProjectFiles;

// Projekte der Gruppe für projektweite Prüfregeln (#1102, unused-public-member):
// Umsetzung von IRuleProjectFiles über den Symbolindex.
//
// - NameIn fragt zuerst die Verwendungen des Index (#492, index.usages, über
//   TIndexUsages). Kann der Index es nicht sagen (index.usages aus, ausgelagert,
//   Unit noch nicht im Index, Wort, das er nicht als Verwendung zählt), sucht
//   NameIn im Text.
// - Units mit Include-Dateien: Was im Text der Unit nicht steht, kann in einer
//   Include-Datei stehen; ist eine davon nicht lesbar, ist die Antwort Unknown.
// - Kind und IsTest leitet KindOfSource bzw. IsTestSource aus dem Hauptquelltext
//   ab, damit die Komposition und der Linter dieselbe Regel anwenden; ProjectOf
//   setzt daraus und aus den Formulardateien neben den Units ein Projekt
//   zusammen (Komposition und MCP-Werkzeug find_unused_code, #64).
// - UsesPath und UsedBy fragen den gemeinsamen Uses-Graph-Dienst (#268, für
//   uses-cycle und unused-unit, #64). Die Komposition reicht ihren
//   langlebigen Dienst herein; ohne ihn baut die Instanz bei Bedarf einen
//   eigenen über den Index (Tests, einmalige Läufe).

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Index.Contract,
  Atlas.Common.Architecture.UsesService,
  Atlas.Common.Rules.Contract;

type
  /// <summary>Text einer Datei, geöffnete Dokumente zuerst; False, wenn sie nicht lesbar ist.</summary>
  TRuleProjectReadText = reference to function(const AFileName: string; out AText: string): Boolean;
  /// <summary>Sind alle Projekte geladen und indiziert? Sonst der Grund in AReason.</summary>
  TRuleProjectComplete = reference to function(out AReason: string): Boolean;

  /// <summary>Bezeichner je Datei für NameIn ohne Verwendungen im Index: Jede Datei wird je Instanz einmal
  /// gelesen und in Tokens zerlegt, nicht für jeden gesuchten Namen neu gelesen und geparst.</summary>
  TRuleFileNames = class
  private
    FLock: TObject;
    /// <summary>Kleingeschriebene Bezeichner je gelesener Datei (Schlüssel in Großbuchstaben).</summary>
    FNames: TObjectDictionary<string, TDictionary<string, Boolean>>;
    function NamesOf(const AFileName: string; const AReadText: TRuleProjectReadText): TDictionary<string, Boolean>;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Bezeichner von AText ohne führendes &amp;, kleingeschrieben.</summary>
    class function Identifiers(const AText: string): TDictionary<string, Boolean>; static;
    /// <summary>Kommt AName als Bezeichner in AFileName vor? Unknown, wenn die Datei nicht lesbar ist.</summary>
    function Lookup(const AFileName, AName: string; const AReadText: TRuleProjectReadText): TRuleNameAnswer;
  end;

  TRuleProjectFiles = class(TInterfacedObject, IRuleProjectFiles)
  private
    FProjects: TArray<TRuleProject>;
    FIndex: ISymbolIndex;
    FReadText: TRuleProjectReadText;
    FComplete: TRuleProjectComplete;
    FUsesGraph: TUsesGraphService;
    FOwnsUsesGraph: Boolean;
    FFileNames: TRuleFileNames;
    /// <summary>Der Uses-Graph-Dienst; ohne hereingereichten einer über FIndex. nil ohne Index.</summary>
    function UsesGraph: TUsesGraphService;
    /// <summary>Steht AName in einer der Include-Dateien? Unknown, wenn eine nicht lesbar ist.</summary>
    function NameInIncludes(const AIncludes: TArray<string>; const AName: string): TRuleNameAnswer;
  public
    /// <summary>AIndex darf nil sein (dann sucht NameIn im Text); AComplete nil = vollständig.</summary>
    constructor Create(const AProjects: TArray<TRuleProject>; const AIndex: ISymbolIndex;
      const AReadText: TRuleProjectReadText; const AComplete: TRuleProjectComplete); overload;
    /// <summary>Wie oben mit dem Uses-Graph-Dienst der Komposition (#64); er gehört dem Aufrufer.</summary>
    constructor Create(const AProjects: TArray<TRuleProject>; const AIndex: ISymbolIndex;
      const AReadText: TRuleProjectReadText; const AComplete: TRuleProjectComplete;
      AUsesGraph: TUsesGraphService); overload;
    destructor Destroy; override;
    function Complete(out AReason: string): Boolean;
    function ProjectsOf(const AFileName: string; AWholeGroup: Boolean): TArray<TRuleProject>;
    function NameIn(const AFileName, AName: string): TRuleNameAnswer;
    function ReadText(const AFileName: string; out AText: string): Boolean;
    function UsesPath(const AFromUnit, AToFile: string; AInterfaceOnly: Boolean): TArray<TRuleUsesStep>;
    function UsedBy(const AFileName: string; out AUsers: TArray<TRuleUsesStep>): Boolean;
    /// <summary>Projekt aus Projektdatei, Hauptquelltext und Units: Art und Testprojekt aus dem Hauptquelltext
    /// (über AReadText), Formulardateien (.dfm, sonst .fmx) neben den Units, sofern sie existieren.</summary>
    class function ProjectOf(const AProjectFile, AMainSource: string; const ASources: TArray<string>;
      const AReadText: TRuleProjectReadText): TRuleProject; static;
    /// <summary>Art des Projekts aus seinem Hauptquelltext: program, library oder package; .dpk ist immer
    /// ein Package.</summary>
    class function KindOfSource(const AFileName, AText: string): TRuleProjectKind; static;
    /// <summary>Bindet der Hauptquelltext ein Test-Framework ein (DUnitX, DUnit, TestInsight)?</summary>
    class function IsTestSource(const AText: string): Boolean; static;
  end;

implementation

uses
  System.StrUtils,
  Atlas.Common.Architecture.UsesGraph,
  Atlas.Common.Index.Usages,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Rules.Profiles;

{ TRuleFileNames }

constructor TRuleFileNames.Create;
begin
  inherited Create;
  FLock := TObject.Create;
  FNames := TObjectDictionary<string, TDictionary<string, Boolean>>.Create([doOwnsValues]);
end;

destructor TRuleFileNames.Destroy;
begin
  FNames.Free;
  FLock.Free;
  inherited;
end;

class function TRuleFileNames.Identifiers(const AText: string): TDictionary<string, Boolean>;
var
  mToken: TPascalToken;
  mName: string;
begin
  Result := TDictionary<string, Boolean>.Create;
  // Nur Bezeichner zählen, nicht Kommentare und Strings; die Tokens reichen, ein Syntaxbaum ist nicht nötig.
  for mToken in TPascalLexer.Tokenize(AText) do
  begin
    if mToken.Kind = TPascalTokenKind.Identifier then
    begin
      mName := mToken.Text;
      if StartsStr('&', mName) then
      begin
        mName := Copy(mName, 2, MaxInt);
      end;
      Result.AddOrSetValue(AnsiLowerCase(mName), True);
    end;
  end;
end;

function TRuleFileNames.NamesOf(const AFileName: string;
  const AReadText: TRuleProjectReadText): TDictionary<string, Boolean>;
var
  mKey, mText: string;
begin
  mKey := AnsiUpperCase(AFileName);
  System.TMonitor.Enter(FLock);
  try
    if FNames.TryGetValue(mKey, Result) then
    begin
      Exit;
    end;
    Result := nil;
    // Nicht lesbare Dateien nicht merken: Sie können während der Prüfung lesbar werden.
    if Assigned(AReadText) and AReadText(AFileName, mText) then
    begin
      Result := Identifiers(mText);
      FNames.Add(mKey, Result);
    end;
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

function TRuleFileNames.Lookup(const AFileName, AName: string;
  const AReadText: TRuleProjectReadText): TRuleNameAnswer;
var
  mNames: TDictionary<string, Boolean>;
begin
  mNames := NamesOf(AFileName, AReadText);
  if mNames = nil then
  begin
    Exit(TRuleNameAnswer.Unknown);
  end;
  Result := TRuleNameAnswer.Absent;
  if mNames.ContainsKey(AnsiLowerCase(AName)) then
  begin
    Result := TRuleNameAnswer.Present;
  end;
end;

{ TRuleProjectFiles }

constructor TRuleProjectFiles.Create(const AProjects: TArray<TRuleProject>; const AIndex: ISymbolIndex;
  const AReadText: TRuleProjectReadText; const AComplete: TRuleProjectComplete);
begin
  inherited Create;
  FFileNames := TRuleFileNames.Create;
  FProjects := AProjects;
  FIndex := AIndex;
  FReadText := AReadText;
  FComplete := AComplete;
end;

constructor TRuleProjectFiles.Create(const AProjects: TArray<TRuleProject>; const AIndex: ISymbolIndex;
  const AReadText: TRuleProjectReadText; const AComplete: TRuleProjectComplete; AUsesGraph: TUsesGraphService);
begin
  Create(AProjects, AIndex, AReadText, AComplete);
  FUsesGraph := AUsesGraph;
end;

destructor TRuleProjectFiles.Destroy;
begin
  if FOwnsUsesGraph then
  begin
    FUsesGraph.Free;
  end;
  FFileNames.Free;
  inherited;
end;

function TRuleProjectFiles.UsesGraph: TUsesGraphService;
begin
  if (FUsesGraph = nil) and (FIndex <> nil) then
  begin
    FUsesGraph := TUsesGraphService.Create(FIndex, TUsesGraphOptions.Default);
    FOwnsUsesGraph := True;
  end;
  Result := FUsesGraph;
end;

function TRuleProjectFiles.UsesPath(const AFromUnit, AToFile: string; AInterfaceOnly: Boolean): TArray<TRuleUsesStep>;
var
  mSteps: TArray<TRuleUsesStep>;
  mFromUnit, mToFile: string;
  mInterfaceOnly: Boolean;
begin
  Result := nil;
  if UsesGraph = nil then
  begin
    Exit;
  end;
  mSteps := nil;
  mFromUnit := AFromUnit;
  mToFile := AToFile;
  mInterfaceOnly := AInterfaceOnly;
  UsesGraph.Read(
    procedure(const AGraph: TUsesGraph)
    var
      Sections: TUsesSections;
      Edge: TUsesEdge;
      Step: TRuleUsesStep;
    begin
      if mInterfaceOnly then
      begin
        Sections := cInterfaceUsesOnly;
      end
      else
      begin
        Sections := cAllUsesSections;
      end;
      for Edge in AGraph.Path(AGraph.IndexOf(mFromUnit), AGraph.IndexOfFile(mToFile), Sections) do
      begin
        Step.UnitName := AGraph.Node(Edge.Target).UnitName;
        Step.FileName := AGraph.Node(Edge.Target).FileName;
        Step.InInterface := Edge.Section = TUsesSection.Interface_;
        Step.SourceFileName := AGraph.Node(Edge.Source).FileName;
        Step.UsesName := Edge.Name;
        mSteps := mSteps + [Step];
      end;
    end);
  Result := mSteps;
end;

function TRuleProjectFiles.UsedBy(const AFileName: string; out AUsers: TArray<TRuleUsesStep>): Boolean;
var
  mUsers: TArray<TRuleUsesStep>;
  mKnown: Boolean;
  mFileName: string;
begin
  AUsers := nil;
  Result := False;
  if UsesGraph = nil then
  begin
    Exit;
  end;
  mUsers := nil;
  mKnown := False;
  mFileName := AFileName;
  UsesGraph.Read(
    procedure(const AGraph: TUsesGraph)
    var
      Node: Integer;
      Ref: TUsesEdgeRef;
      Source: TUsesNode;
      Step: TRuleUsesStep;
    begin
      Node := AGraph.IndexOfFile(mFileName);
      if Node < 0 then
      begin
        Exit;
      end;
      mKnown := True;
      for Ref in AGraph.Node(Node).Incoming do
      begin
        Source := AGraph.Node(Ref.Source);
        if not Source.Active then
        begin
          Continue;
        end;
        Step.UnitName := Source.UnitName;
        Step.FileName := Source.FileName;
        Step.InInterface := Source.Outgoing[Ref.Item].Section = TUsesSection.Interface_;
        Step.SourceFileName := Source.FileName;
        Step.UsesName := Source.Outgoing[Ref.Item].Name;
        mUsers := mUsers + [Step];
      end;
    end);
  AUsers := mUsers;
  Result := mKnown;
end;

class function TRuleProjectFiles.ProjectOf(const AProjectFile, AMainSource: string; const ASources: TArray<string>;
  const AReadText: TRuleProjectReadText): TRuleProject;
var
  mText, mSource: string;
begin
  Result := Default(TRuleProject);
  Result.FileName := AProjectFile;
  Result.Sources := ASources;
  if Assigned(AReadText) and AReadText(AMainSource, mText) then
  begin
    Result.Kind := KindOfSource(AMainSource, mText);
    Result.IsTest := IsTestSource(mText);
  end
  else if SameText(ExtractFileExt(AMainSource), '.dpk') then
  begin
    Result.Kind := TRuleProjectKind.Package;
  end;
  for mSource in ASources do
  begin
    if SameText(ExtractFileExt(mSource), '.pas') then
    begin
      if FileExists(ChangeFileExt(mSource, '.dfm')) then
      begin
        Result.Forms := Result.Forms + [ChangeFileExt(mSource, '.dfm')];
      end
      else if FileExists(ChangeFileExt(mSource, '.fmx')) then
      begin
        Result.Forms := Result.Forms + [ChangeFileExt(mSource, '.fmx')];
      end;
    end;
  end;
end;

function TRuleProjectFiles.Complete(out AReason: string): Boolean;
begin
  AReason := '';
  if Assigned(FComplete) then
  begin
    Result := FComplete(AReason);
  end
  else
  begin
    Result := True;
  end;
end;

function TRuleProjectFiles.ProjectsOf(const AFileName: string; AWholeGroup: Boolean): TArray<TRuleProject>;
var
  mProject: TRuleProject;
  mSource: string;
  mMember: Boolean;
  mOthers: TArray<TRuleProject>;
begin
  Result := nil;
  mOthers := nil;
  for mProject in FProjects do
  begin
    mMember := False;
    for mSource in mProject.Sources do
    begin
      if SameText(mSource, AFileName) then
      begin
        mMember := True;
      end;
    end;
    if mMember then
    begin
      Result := Result + [mProject];
    end
    else
    begin
      mOthers := mOthers + [mProject];
    end;
  end;
  if AWholeGroup and (Result <> nil) then
  begin
    Result := Result + mOthers;
  end;
end;

function TRuleProjectFiles.ReadText(const AFileName: string; out AText: string): Boolean;
begin
  AText := '';
  Result := Assigned(FReadText) and FReadText(AFileName, AText);
end;

function TRuleProjectFiles.NameIn(const AFileName, AName: string): TRuleNameAnswer;
var
  mIndexed: TUnitIndex;
  mHasUnit: Boolean;
begin
  mHasUnit := (FIndex <> nil) and FIndex.FindFile(AFileName, mIndexed);
  if mHasUnit then
    // Deklarationen zählen nicht als Verwendung; der Name kann trotzdem als Deklaration in der Datei stehen.
    case TIndexUsages.Lookup(mIndexed, AName) of
      TIndexUsageAnswer.Present:
        Exit(TRuleNameAnswer.Present);
      TIndexUsageAnswer.Absent:
        Exit(TRuleNameAnswer.Absent);
    end;
  // Ohne Verwendungen (ausgelagert, aus): Bezeichner der Datei, je Datei einmal gelesen.
  Result := FFileNames.Lookup(AFileName, AName, FReadText);
  if mHasUnit and (Result = TRuleNameAnswer.Absent) then
  begin
    Result := NameInIncludes(mIndexed.Includes, AName);
  end;
end;

function TRuleProjectFiles.NameInIncludes(const AIncludes: TArray<string>; const AName: string): TRuleNameAnswer;
var
  mInclude: string;
begin
  Result := TRuleNameAnswer.Absent;
  for mInclude in AIncludes do
  begin
    Result := FFileNames.Lookup(mInclude, AName, FReadText);
    if Result <> TRuleNameAnswer.Absent then
    begin
      Exit;
    end;
  end;
end;

class function TRuleProjectFiles.KindOfSource(const AFileName, AText: string): TRuleProjectKind;
var
  mTree: TSyntaxTree;
  mToken: TPascalToken;
begin
  if SameText(ExtractFileExt(AFileName), '.dpk') then
  begin
    Exit(TRuleProjectKind.Package);
  end;
  Result := TRuleProjectKind.Unknown;
  mTree := TSyntaxTreeCache.Parse(AText);
  try
    for mToken in mTree.Tokens do
    begin
      if mToken.Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Keyword] then
      begin
        if SameText(mToken.Text, 'program') then
        begin
          Result := TRuleProjectKind.Application;
        end
        else if SameText(mToken.Text, 'library') then
        begin
          Result := TRuleProjectKind.Library_;
        end
        else if SameText(mToken.Text, 'package') then
        begin
          Result := TRuleProjectKind.Package;
        end;
        Exit;
      end;
    end;
  finally
    mTree.Free;
  end;
end;

class function TRuleProjectFiles.IsTestSource(const AText: string): Boolean;
var
  mTree: TSyntaxTree;
begin
  mTree := TSyntaxTreeCache.Parse(AText);
  try
    Result := TRuleProfiles.IsTestUnit(mTree.Tokens);
  finally
    mTree.Free;
  end;
end;

end.
