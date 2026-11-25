unit Atlas.Common.Architecture.Adapters.GroupFiles;

// Projekte der Gruppe für projektweite Auswertungen (#1102, unused-public-member):
// Umsetzung von IProjectGroupFiles über den Symbolindex.
//
// - NameIn fragt zuerst die Verwendungen des Index (#492, index.usages, über
//   TIndexUsages). Kann der Index es nicht sagen (index.usages aus, ausgelagert,
//   Unit noch nicht im Index, Wort, das er nicht als Verwendung zählt), sucht
//   NameIn im Text.
// - Units mit Include-Dateien: Was im Text der Unit nicht steht, kann in einer
//   Include-Datei stehen; ist eine davon nicht lesbar, ist die Antwort Unknown.
// - Die Projekte selbst setzt TGroupProjects (Atlas.Common.Projects.GroupProjects)
//   zusammen; die Komposition erzeugt diese Umsetzung über die Fabrik des
//   Arbeitsbereichs (TCoreWorkspaceFactories.GroupFiles).
// - UsesPath und UsedBy fragen den gemeinsamen Uses-Graph-Dienst (#268, für
//   uses-cycle und unused-unit, #64). Die Komposition reicht ihren
//   langlebigen Dienst herein; ohne ihn baut die Instanz bei Bedarf einen
//   eigenen über den Index (Tests, einmalige Läufe).
// - UsesDerived reicht die Kanten zwischen Units (ohne Programme und
//   Packages, deren contains alles verbindet) an eine Ableitung des Dienstes.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Index.Contract,
  Atlas.Common.Architecture.UsesService,
  Atlas.Common.Projects.Contract.Group;

type
  /// <summary>Bezeichner je Datei für NameIn ohne Verwendungen im Index: Jede Datei wird je Instanz einmal
  /// gelesen und in Tokens zerlegt, nicht für jeden gesuchten Namen neu gelesen und geparst.</summary>
  TProjectFileNames = class
  private
    FLock: TObject;
    /// <summary>Kleingeschriebene Bezeichner je gelesener Datei (Schlüssel in Großbuchstaben).</summary>
    FNames: TObjectDictionary<string, TDictionary<string, Boolean>>;
    function NamesOf(const AFileName: string; const AReadText: TProjectReadText): TDictionary<string, Boolean>;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Bezeichner von AText ohne führendes &amp;, kleingeschrieben.</summary>
    class function Identifiers(const AText: string): TDictionary<string, Boolean>; static;
    /// <summary>Kommt AName als Bezeichner in AFileName vor? Unknown, wenn die Datei nicht lesbar ist.</summary>
    function Lookup(const AFileName, AName: string; const AReadText: TProjectReadText): TNameAnswer;
  end;

  TProjectGroupFiles = class(TInterfacedObject, IProjectGroupFiles)
  private
    FProjects: TArray<TGroupProject>;
    FIndex: ISymbolIndex;
    FReadText: TProjectReadText;
    FComplete: TProjectGroupComplete;
    FUsesGraph: TUsesGraphService;
    FOwnsUsesGraph: Boolean;
    FFileNames: TProjectFileNames;
    /// <summary>Der Uses-Graph-Dienst; ohne hereingereichten einer über FIndex. nil ohne Index.</summary>
    function UsesGraph: TUsesGraphService;
    /// <summary>Steht AName in einer der Include-Dateien? Unknown, wenn eine nicht lesbar ist.</summary>
    function NameInIncludes(const AIncludes: TArray<string>; const AName: string): TNameAnswer;
  public
    /// <summary>AIndex darf nil sein (dann sucht NameIn im Text); AComplete nil = vollständig.</summary>
    constructor Create(const AProjects: TArray<TGroupProject>; const AIndex: ISymbolIndex;
      const AReadText: TProjectReadText; const AComplete: TProjectGroupComplete); overload;
    /// <summary>Wie oben mit dem Uses-Graph-Dienst der Komposition (#64); er gehört dem Aufrufer.</summary>
    constructor Create(const AProjects: TArray<TGroupProject>; const AIndex: ISymbolIndex;
      const AReadText: TProjectReadText; const AComplete: TProjectGroupComplete;
      AUsesGraph: TUsesGraphService); overload;
    destructor Destroy; override;
    function Complete(out AReason: string): Boolean;
    function ProjectsOf(const AFileName: string; AWholeGroup: Boolean): TArray<TGroupProject>;
    function NameIn(const AFileName, AName: string): TNameAnswer;
    function ReadText(const AFileName: string; out AText: string): Boolean;
    function UsesPath(const AFromUnit, AToFile: string; AInterfaceOnly: Boolean): TArray<TGroupUsesStep>;
    function UsedBy(const AFileName: string; out AUsers: TArray<TGroupUsesStep>): Boolean;
    function UsesDerived(const AKey: string; const ADerive: TGroupUsesDerive): IInterface;
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
  Atlas.Common.Pascal.UsesClauses;

{ TProjectFileNames }

constructor TProjectFileNames.Create;
begin
  inherited Create;
  FLock := TObject.Create;
  FNames := TObjectDictionary<string, TDictionary<string, Boolean>>.Create([doOwnsValues]);
end;

destructor TProjectFileNames.Destroy;
begin
  FNames.Free;
  FLock.Free;
  inherited;
end;

function TProjectFileNames.NamesOf(const AFileName: string;
  const AReadText: TProjectReadText): TDictionary<string, Boolean>;
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

class function TProjectFileNames.Identifiers(const AText: string): TDictionary<string, Boolean>;
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

function TProjectFileNames.Lookup(const AFileName, AName: string;
  const AReadText: TProjectReadText): TNameAnswer;
var
  mNames: TDictionary<string, Boolean>;
begin
  mNames := NamesOf(AFileName, AReadText);
  if mNames = nil then
  begin
    Exit(TNameAnswer.Unknown);
  end;
  Result := TNameAnswer.Absent;
  if mNames.ContainsKey(AnsiLowerCase(AName)) then
  begin
    Result := TNameAnswer.Present;
  end;
end;

{ TProjectGroupFiles }

constructor TProjectGroupFiles.Create(const AProjects: TArray<TGroupProject>; const AIndex: ISymbolIndex;
  const AReadText: TProjectReadText; const AComplete: TProjectGroupComplete);
begin
  inherited Create;
  FFileNames := TProjectFileNames.Create;
  FProjects := AProjects;
  FIndex := AIndex;
  FReadText := AReadText;
  FComplete := AComplete;
end;

constructor TProjectGroupFiles.Create(const AProjects: TArray<TGroupProject>; const AIndex: ISymbolIndex;
  const AReadText: TProjectReadText; const AComplete: TProjectGroupComplete; AUsesGraph: TUsesGraphService);
begin
  Create(AProjects, AIndex, AReadText, AComplete);
  FUsesGraph := AUsesGraph;
end;

destructor TProjectGroupFiles.Destroy;
begin
  if FOwnsUsesGraph then
  begin
    FUsesGraph.Free;
  end;
  FFileNames.Free;
  inherited;
end;

function TProjectGroupFiles.UsesGraph: TUsesGraphService;
begin
  if (FUsesGraph = nil) and (FIndex <> nil) then
  begin
    FUsesGraph := TUsesGraphService.Create(FIndex, TUsesGraphOptions.Default);
    FOwnsUsesGraph := True;
  end;
  Result := FUsesGraph;
end;

function TProjectGroupFiles.NameInIncludes(const AIncludes: TArray<string>; const AName: string): TNameAnswer;
var
  mInclude: string;
begin
  Result := TNameAnswer.Absent;
  for mInclude in AIncludes do
  begin
    Result := FFileNames.Lookup(mInclude, AName, FReadText);
    if Result <> TNameAnswer.Absent then
    begin
      Exit;
    end;
  end;
end;

function TProjectGroupFiles.Complete(out AReason: string): Boolean;
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

function TProjectGroupFiles.ProjectsOf(const AFileName: string; AWholeGroup: Boolean): TArray<TGroupProject>;
var
  mProject: TGroupProject;
  mSource: string;
  mMember: Boolean;
  mOthers: TArray<TGroupProject>;
begin
  // '' liefert alle Projekte der Gruppe, z. B. für eine Unit, die in keinem Projekt steht (#1882).
  if AFileName = '' then
  begin
    Exit(FProjects);
  end;
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

function TProjectGroupFiles.NameIn(const AFileName, AName: string): TNameAnswer;
var
  mIndexed: TUnitIndex;
  mHasUnit: Boolean;
begin
  mHasUnit := (FIndex <> nil) and FIndex.FindFile(AFileName, mIndexed);
  if mHasUnit then
    // Deklarationen zählen nicht als Verwendung; der Name kann trotzdem als Deklaration in der Datei stehen.
    case TIndexUsages.Lookup(mIndexed, AName) of
      TIndexUsageAnswer.Present:
        Exit(TNameAnswer.Present);
      TIndexUsageAnswer.Absent:
        Exit(TNameAnswer.Absent);
    end;
  // Ohne Verwendungen (ausgelagert, aus): Bezeichner der Datei, je Datei einmal gelesen.
  Result := FFileNames.Lookup(AFileName, AName, FReadText);
  if mHasUnit and (Result = TNameAnswer.Absent) then
  begin
    Result := NameInIncludes(mIndexed.Includes, AName);
  end;
end;

function TProjectGroupFiles.ReadText(const AFileName: string; out AText: string): Boolean;
begin
  AText := '';
  Result := Assigned(FReadText) and FReadText(AFileName, AText);
end;

function TProjectGroupFiles.UsesPath(const AFromUnit, AToFile: string; AInterfaceOnly: Boolean): TArray<TGroupUsesStep>;
var
  mSteps: TArray<TGroupUsesStep>;
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
      Step: TGroupUsesStep;
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

function TProjectGroupFiles.UsedBy(const AFileName: string; out AUsers: TArray<TGroupUsesStep>): Boolean;
var
  mUsers: TArray<TGroupUsesStep>;
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
      Step: TGroupUsesStep;
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

function TProjectGroupFiles.UsesDerived(const AKey: string; const ADerive: TGroupUsesDerive): IInterface;
var
  mDerive: TGroupUsesDerive;
begin
  Result := nil;
  if UsesGraph = nil then
  begin
    Exit;
  end;
  mDerive := ADerive;
  Result := UsesGraph.Derived(AKey,
    function(const AGraph: TUsesGraph): IInterface
    var
      Edges: TArray<TGroupUsesEdge>;
      Count, NodeIndex: Integer;
      Source: TUsesNode;
      Edge: TUsesEdge;
    begin
      Count := 0;
      SetLength(Edges, AGraph.EdgeCount);
      for NodeIndex := 0 to AGraph.NodeCount - 1 do
      begin
        Source := AGraph.Node(NodeIndex);
        if not Source.Active or Source.IsProgram then
        begin
          Continue;
        end;
        for Edge in Source.Outgoing do
        begin
          if Count >= Length(Edges) then
          begin
            SetLength(Edges, 2 * Count + 16);
          end;
          Edges[Count].SourceUnit := Source.UnitName;
          Edges[Count].SourceFileName := Source.FileName;
          Edges[Count].TargetUnit := AGraph.Node(Edge.Target).UnitName;
          Edges[Count].TargetFileName := AGraph.Node(Edge.Target).FileName;
          Edges[Count].InInterface := Edge.Section = TUsesSection.Interface_;
          Inc(Count);
        end;
      end;
      SetLength(Edges, Count);
      Result := mDerive(Edges);
    end);
end;

end.
