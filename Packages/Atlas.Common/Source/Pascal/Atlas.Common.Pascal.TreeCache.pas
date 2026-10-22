unit Atlas.Common.Pascal.TreeCache;

// Gemeinsamer Syntaxbaum je Dokumentversion (#262). Alle Features holen den
// Baum eines geöffneten Dokuments hier ab, statt selbst zu parsen:
// - Der Baum hängt an der unveränderlichen Momentaufnahme (ITextDocument.Derived).
//   Der erste Zugriff parst, gleichzeitige Zugriffe warten auf dasselbe Ergebnis.
// - Der Baum ist unveränderlich und referenzgezählt (ISharedSyntaxTree). Ältere
//   Versionen werden frei, sobald weder Dokument noch Feature sie mehr halten.
// - Wird für eine Datei eine neuere Version geparst, bricht ein noch laufender
//   Parse der älteren ab; sein unvollständiger Baum wird nicht abgelegt.
// - Get liefert den Baum nur aus den aktiven {$IFDEF}-Zweigen (#845), mit den
//   Symbolen des Projekts aus dem DefinesProvider (ohne: Vordefinitionen). Die
//   Symbole gehören zum Schlüssel: Nach einem Wechsel von Plattform oder
//   Konfiguration parst der nächste Zugriff neu. GetAll liefert den Baum aus
//   allen Zweigen für Funktionen, die bewusst beide Seiten sehen müssen.
// - Mit IncludeProvider (#860) liest der Präprozessor {$I datei.inc}: Dort
//   gesetzte Symbole wählen die Zweige der Datei. Der Lauf steht in Processed,
//   damit Abblenden, Include-Befunde und Inlay-Hinweise ihn nicht wiederholen.
//   Ändert sich eine Include-Datei, macht IncludesChanged die Bäume mit $I ungültig.
// Texte ohne geöffnetes Dokument (Index, andere Dateien, Kommandozeile) parst
// Parse ohne Cache; dort gilt das Speicherbudget aus #185.

interface

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Preprocessor,
  Atlas.Common.Pascal.SyntaxTree;

type
  /// <summary>Gemeinsam genutzter Syntaxbaum; nur lesen, nicht freigeben.</summary>
  ISharedSyntaxTree = interface
    ['{5E2B7C14-9A3D-4F61-B8E2-3C7D0A9F1B46}']
    function Tree: TSyntaxTree;
    /// <summary>Zweige der bedingten Kompilierung mit Bedingung und ob sie gelten; leer beim Vollbaum
    /// und bei Texten ohne bedingte Direktive.</summary>
    function Conditionals: TArray<TConditionalRange>;
    /// <summary>Präprozessor-Lauf zum Baum (#860); Files leer, wenn keiner nötig war (Vollbaum, Text ohne
    /// bedingte Direktive und ohne auflösbares $I).</summary>
    function Processed: TPreprocessorResult;
    /// <summary>Lief der Präprozessor mit Include-Resolver? Nur dann sind Include-Befunde echt.</summary>
    function IncludesResolved: Boolean;
  end;

  /// <summary>Symbole des Projekts zu einer Datei; False, wenn keine bekannt sind.</summary>
  TTreeDefinesProvider = reference to function(const AUri: string; out ADefines: TArray<string>): Boolean;

  /// <summary>Include-Resolver zu einer Datei (#860, Server: Suchpfade ihres Projekts); nil = $I nicht lesen.
  /// </summary>
  TTreeIncludeProvider = reference to function(const AUri: string): TIncludeResolver;

  TSyntaxTreeCache = class
  public
    /// <summary>Baum der Momentaufnahme aus den aktiven Zweigen, höchstens einmal je Version und
    /// Symbolstand geparst. ACancellation bricht nur den Ausweichweg ab, wenn der gemeinsame Parse von
    /// einer neueren Version überholt wurde.</summary>
    class function Get(const ADocument: ITextDocument;
      const ACancellation: IPascalCancellation = nil): ISharedSyntaxTree; static;
    /// <summary>Wie Get, mit ausdrücklichen Symbolen statt denen des DefinesProvider.</summary>
    class function GetFor(const ADocument: ITextDocument; const ADefines: TArray<string>;
      const ACancellation: IPascalCancellation = nil): ISharedSyntaxTree; static;
    /// <summary>Wie Get, aber aus allen Zweigen der bedingten Kompilierung (#845).</summary>
    class function GetAll(const ADocument: ITextDocument;
      const ACancellation: IPascalCancellation = nil): ISharedSyntaxTree; static;
    /// <summary>Symbole, unter denen Get die Datei liest; leer = Vordefinitionen.</summary>
    class function DefinesOf(const AUri: string): TArray<string>; static;
    /// <summary>Quelle der Projektsymbole (Server: aktives Projekt der Datei); nil = Vordefinitionen.</summary>
    class procedure SetDefinesProvider(const AProvider: TTreeDefinesProvider); static;
    /// <summary>Quelle der Include-Resolver (#860); nil = {$I} wird nicht gelesen.</summary>
    class procedure SetIncludeProvider(const AProvider: TTreeIncludeProvider); static;
    /// <summary>Include-Resolver, mit dem Get die Datei liest; nil ohne IncludeProvider.</summary>
    class function IncludeResolverOf(const AUri: string): TIncludeResolver; static;
    /// <summary>Eine Include-Datei hat sich geändert: Bäume von Texten mit $I werden beim nächsten Zugriff
    /// neu geparst.</summary>
    class procedure IncludesChanged; static;
    /// <summary>Parst ohne Cache; der Aufrufer gibt den Baum frei.</summary>
    class function Parse(const AText: string; const ACancellation: IPascalCancellation = nil): TSyntaxTree; static;
    /// <summary>Wie Parse, aus den aktiven Zweigen unter AOptions (Dateiname, Include-Resolver, #860); AProcessed
    /// erhält den Präprozessor-Lauf.</summary>
    class function ParseActive(const AText: string; const AOptions: TPreprocessorOptions;
      const ACancellation: IPascalCancellation; out AProcessed: TPreprocessorResult): TSyntaxTree; static;
    /// <summary>Anzahl der Parse-Läufe über Get seit Programmstart, für Tests und Status.</summary>
    class function ParseCount: Integer; static;
  end;

implementation

uses
  System.SyncObjs,
  System.Generics.Collections,
  System.Generics.Defaults,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Pascal.Parser;

const
  TreeKey = 'pascal.syntaxtree';
  /// <summary>Schlüssel des Vollbaums aus allen Zweigen.</summary>
  AllKey = 'pascal.syntaxtree.all';

type
  TSharedSyntaxTree = class(TInterfacedObject, ISharedSyntaxTree)
  private
    FTree: TSyntaxTree;
    FConditionals: TArray<TConditionalRange>;
    FProcessed: TPreprocessorResult;
    FIncludesResolved: Boolean;
  public
    constructor Create(ATree: TSyntaxTree; const AProcessed: TPreprocessorResult; AIncludesResolved: Boolean);
    destructor Destroy; override;
    function Tree: TSyntaxTree;
    function Conditionals: TArray<TConditionalRange>;
    function Processed: TPreprocessorResult;
    function IncludesResolved: Boolean;
  end;

  /// <summary>Abbruchsignal eines gemeinsamen Parse-Laufs.</summary>
  TParseRun = class(TInterfacedObject, IPascalCancellation)
  private
    FVersion: Integer;
    FCancelled: Integer;
  public
    constructor Create(AVersion: Integer);
    procedure Cancel;
    function IsCancelled: Boolean;
    property Version: Integer read FVersion;
  end;

  /// <summary>Wie ein Baum entsteht: aus allen oder nur aus den aktiven Zweigen.</summary>
  TTreeMode = record
    All: Boolean;
    Defines: TArray<string>;
    FileName: string;
    Resolver: TIncludeResolver;
    function Key(const AText: string): string;
    function ReadsIncludes(const AText: string): Boolean;
  end;

var
  // TCriticalSection statt TMonitor: TMonitor legt Sperrdaten erst beim ersten Zugriff
  // bzw. Konflikt an und behält sie; der Leck-Monitor meldete das im ersten Test.
  RunLock: TCriticalSection;
  // Laufender gemeinsamer Parse je URI und Schlüssel; hält die Läufe über ihre Schnittstelle am Leben.
  Running: TDictionary<string, IPascalCancellation>;
  Parses: Integer;
  DefinesProvider: TTreeDefinesProvider;
  IncludeProvider: TTreeIncludeProvider;
  // Stand der Include-Dateien; gehört bei Texten mit $I zum Schlüssel.
  IncludeGeneration: Integer;

{ TSharedSyntaxTree }

constructor TSharedSyntaxTree.Create(ATree: TSyntaxTree; const AProcessed: TPreprocessorResult;
  AIncludesResolved: Boolean);
begin
  inherited Create;
  FTree := ATree;
  FProcessed := AProcessed;
  FIncludesResolved := AIncludesResolved;
  FConditionals := TPascalPreprocessor.MainConditionals(AProcessed);
end;

destructor TSharedSyntaxTree.Destroy;
begin
  FTree.Free;
  inherited;
end;

function TSharedSyntaxTree.Tree: TSyntaxTree;
begin
  Result := FTree;
end;

function TSharedSyntaxTree.Conditionals: TArray<TConditionalRange>;
begin
  Result := FConditionals;
end;

function TSharedSyntaxTree.Processed: TPreprocessorResult;
begin
  Result := FProcessed;
end;

function TSharedSyntaxTree.IncludesResolved: Boolean;
begin
  Result := FIncludesResolved;
end;

{ TParseRun }

constructor TParseRun.Create(AVersion: Integer);
begin
  inherited Create;
  FVersion := AVersion;
end;

procedure TParseRun.Cancel;
begin
  TInterlocked.Exchange(FCancelled, 1);
end;

function TParseRun.IsCancelled: Boolean;
begin
  Result := TInterlocked.CompareExchange(FCancelled, 0, 0) = 1;
end;

{ TTreeMode }

function TTreeMode.Key(const AText: string): string;
var
  Sorted: TArray<string>;
  Index: Integer;
begin
  if All then
    Exit(AllKey);
  // Ohne bedingte Direktive und $I ist der Baum für alle Symbole gleich: kein neuer Parse beim Plattformwechsel.
  if not TPascalPreprocessor.HasConditionals(AText) and not ReadsIncludes(AText) then
    Exit(TreeKey);
  Sorted := Copy(Defines);
  for Index := 0 to High(Sorted) do
    Sorted[Index] := UpperCase(Trim(Sorted[Index]));
  TArray.Sort<string>(Sorted);
  Result := TreeKey + '|' + string.Join(';', Sorted);
  if ReadsIncludes(AText) then
    Result := Result + '|inc' + IntToStr(TInterlocked.CompareExchange(IncludeGeneration, 0, 0));
end;

function TTreeMode.ReadsIncludes(const AText: string): Boolean;
begin
  Result := not All and Assigned(Resolver) and TPascalPreprocessor.HasIncludes(AText);
end;

/// <summary>Baum nach AMode ohne Cache.</summary>
function ParseFor(const AText: string; const AMode: TTreeMode;
  const ACancellation: IPascalCancellation): ISharedSyntaxTree;
var
  Processed: TPreprocessorResult;
  Tree: TSyntaxTree;
begin
  Processed := Default(TPreprocessorResult);
  if AMode.All then
    Tree := TPascalParser.Parse(AText, ACancellation)
  else
    Tree := TPascalParser.ParseActive(AText, TPascalPreprocessor.EditorOptions(AMode.Defines, AMode.FileName,
      AMode.Resolver), ACancellation, Processed);
  Result := TSharedSyntaxTree.Create(Tree, Processed, AMode.ReadsIncludes(AText));
end;

/// <summary>Parst ADocument als gemeinsamen Lauf; nil, wenn eine neuere Version ihn überholt hat.</summary>
function ParseShared(const ADocument: ITextDocument; const AMode: TTreeMode; const AKey: string): IInterface;
var
  Run: TParseRun;
  Signal: IPascalCancellation;
  Previous: IPascalCancellation;
  Shared: ISharedSyntaxTree;
  RunKey: string;
begin
  RunKey := ADocument.Uri + #0 + AKey;
  Run := TParseRun.Create(ADocument.Version);
  Signal := Run;
  RunLock.Enter;
  try
    if not Running.TryGetValue(RunKey, Previous) then
      Running.Add(RunKey, Signal)
    else if (Previous as TParseRun).Version < ADocument.Version then
    begin
      (Previous as TParseRun).Cancel;
      Running[RunKey] := Signal;
    end;
    // Ist schon eine neuere Version in Arbeit, läuft dieser Parse ohne Eintrag zu Ende.
  finally
    RunLock.Leave;
  end;
  Shared := ParseFor(ADocument.Text, AMode, Signal);
  TInterlocked.Increment(Parses);
  RunLock.Enter;
  try
    if Running.TryGetValue(RunKey, Previous) and (Previous = Signal) then
      Running.Remove(RunKey);
  finally
    RunLock.Leave;
  end;
  if Run.IsCancelled then
    Exit(nil);
  Result := Shared;
end;

/// <summary>Gemeinsamer Baum der Momentaufnahme nach AMode.</summary>
function GetShared(const ADocument: ITextDocument; const AMode: TTreeMode;
  const ACancellation: IPascalCancellation): ISharedSyntaxTree;
var
  Document: ITextDocument;
  Mode: TTreeMode;
  Key: string;
  Value: IInterface;
begin
  Document := ADocument;
  Mode := AMode;
  Key := Mode.Key(Document.Text);
  Value := Document.Derived(Key,
    function: IInterface
    begin
      Result := ParseShared(Document, Mode, Key);
    end);
  if Supports(Value, ISharedSyntaxTree, Result) then
    Exit;
  // Von einer neueren Version überholt: für diese (veraltete) Anfrage ohne Cache parsen.
  Result := ParseFor(Document.Text, Mode, ACancellation);
end;

{ TSyntaxTreeCache }

class function TSyntaxTreeCache.Get(const ADocument: ITextDocument;
  const ACancellation: IPascalCancellation): ISharedSyntaxTree;
begin
  Result := GetFor(ADocument, DefinesOf(ADocument.Uri), ACancellation);
end;

class function TSyntaxTreeCache.GetFor(const ADocument: ITextDocument; const ADefines: TArray<string>;
  const ACancellation: IPascalCancellation): ISharedSyntaxTree;
var
  Mode: TTreeMode;
begin
  Mode.All := False;
  Mode.Defines := ADefines;
  Mode.FileName := TDocumentUris.ToPath(ADocument.Uri);
  Mode.Resolver := IncludeResolverOf(ADocument.Uri);
  Result := GetShared(ADocument, Mode, ACancellation);
end;

class function TSyntaxTreeCache.GetAll(const ADocument: ITextDocument;
  const ACancellation: IPascalCancellation): ISharedSyntaxTree;
var
  Mode: TTreeMode;
begin
  Mode.All := True;
  Mode.Defines := nil;
  Mode.FileName := '';
  Mode.Resolver := nil;
  Result := GetShared(ADocument, Mode, ACancellation);
end;

class function TSyntaxTreeCache.DefinesOf(const AUri: string): TArray<string>;
var
  Provider: TTreeDefinesProvider;
begin
  RunLock.Enter;
  try
    Provider := DefinesProvider;
  finally
    RunLock.Leave;
  end;
  Result := nil;
  if Assigned(Provider) and not Provider(AUri, Result) then
    Result := nil;
end;

class procedure TSyntaxTreeCache.SetDefinesProvider(const AProvider: TTreeDefinesProvider);
begin
  RunLock.Enter;
  try
    DefinesProvider := AProvider;
  finally
    RunLock.Leave;
  end;
end;

class procedure TSyntaxTreeCache.SetIncludeProvider(const AProvider: TTreeIncludeProvider);
begin
  RunLock.Enter;
  try
    IncludeProvider := AProvider;
  finally
    RunLock.Leave;
  end;
end;

class function TSyntaxTreeCache.IncludeResolverOf(const AUri: string): TIncludeResolver;
var
  Provider: TTreeIncludeProvider;
begin
  RunLock.Enter;
  try
    Provider := IncludeProvider;
  finally
    RunLock.Leave;
  end;
  Result := nil;
  if Assigned(Provider) then
    Result := Provider(AUri);
end;

class procedure TSyntaxTreeCache.IncludesChanged;
begin
  TInterlocked.Increment(IncludeGeneration);
end;

class function TSyntaxTreeCache.Parse(const AText: string; const ACancellation: IPascalCancellation): TSyntaxTree;
begin
  Result := TPascalParser.Parse(AText, ACancellation);
end;

class function TSyntaxTreeCache.ParseActive(const AText: string; const AOptions: TPreprocessorOptions;
  const ACancellation: IPascalCancellation; out AProcessed: TPreprocessorResult): TSyntaxTree;
begin
  Result := TPascalParser.ParseActive(AText, AOptions, ACancellation, AProcessed);
end;

class function TSyntaxTreeCache.ParseCount: Integer;
begin
  Result := TInterlocked.CompareExchange(Parses, 0, 0);
end;

initialization
  RunLock := TCriticalSection.Create;
  // Gleich mit Platz anlegen: Wächst das Wörterbuch erst beim ersten Parse, bleibt der
  // vergrößerte Speicher bis Programmende liegen und gilt im Test als Leck.
  Running := TDictionary<string, IPascalCancellation>.Create(64);

finalization
  DefinesProvider := nil;
  IncludeProvider := nil;
  FreeAndNil(Running);
  FreeAndNil(RunLock);

end.
