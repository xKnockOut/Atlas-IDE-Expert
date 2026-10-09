unit Argus.Common.Pascal.TreeCache;

// Gemeinsamer Syntaxbaum je Dokumentversion (#262). Alle Features holen den
// Baum eines geöffneten Dokuments hier ab, statt selbst zu parsen:
// - Der Baum hängt an der unveränderlichen Momentaufnahme (ITextDocument.Derived).
//   Der erste Zugriff parst, gleichzeitige Zugriffe warten auf dasselbe Ergebnis.
// - Der Baum ist unveränderlich und referenzgezählt (ISharedSyntaxTree). Ältere
//   Versionen werden frei, sobald weder Dokument noch Feature sie mehr halten.
// - Wird für eine Datei eine neuere Version geparst, bricht ein noch laufender
//   Parse der älteren ab; sein unvollständiger Baum wird nicht abgelegt.
// Texte ohne geöffnetes Dokument (Index, andere Dateien, Kommandozeile) parst
// Parse ohne Cache; dort gilt das Speicherbudget aus #185.

interface

uses
  System.SysUtils,
  Argus.Common.Documents.Contract,
  Argus.Common.Pascal.Contract,
  Argus.Common.Pascal.SyntaxTree;

type
  /// <summary>Gemeinsam genutzter Syntaxbaum; nur lesen, nicht freigeben.</summary>
  ISharedSyntaxTree = interface
    ['{5E2B7C14-9A3D-4F61-B8E2-3C7D0A9F1B46}']
    function Tree: TSyntaxTree;
  end;

  TSyntaxTreeCache = class
  public
    /// <summary>Baum der Momentaufnahme, höchstens einmal je Version geparst. ACancellation bricht
    /// nur den Ausweichweg ab, wenn der gemeinsame Parse von einer neueren Version überholt wurde.</summary>
    class function Get(const ADocument: ITextDocument;
      const ACancellation: IPascalCancellation = nil): ISharedSyntaxTree; static;
    /// <summary>Parst ohne Cache; der Aufrufer gibt den Baum frei.</summary>
    class function Parse(const AText: string; const ACancellation: IPascalCancellation = nil): TSyntaxTree; static;
    /// <summary>Anzahl der Parse-Läufe über Get seit Programmstart, für Tests und Status.</summary>
    class function ParseCount: Integer; static;
  end;

implementation

uses
  System.SyncObjs,
  System.Generics.Collections,
  Argus.Common.Pascal.Parser;

const
  TreeKey = 'pascal.syntaxtree';

type
  TSharedSyntaxTree = class(TInterfacedObject, ISharedSyntaxTree)
  private
    FTree: TSyntaxTree;
  public
    constructor Create(ATree: TSyntaxTree);
    destructor Destroy; override;
    function Tree: TSyntaxTree;
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

var
  // TCriticalSection statt TMonitor: TMonitor legt Sperrdaten erst beim ersten Zugriff
  // bzw. Konflikt an und behält sie; der Leck-Monitor meldete das im ersten Test.
  RunLock: TCriticalSection;
  // Laufender gemeinsamer Parse je URI; hält die Läufe über ihre Schnittstelle am Leben.
  Running: TDictionary<string, IPascalCancellation>;
  Parses: Integer;

{ TSharedSyntaxTree }

constructor TSharedSyntaxTree.Create(ATree: TSyntaxTree);
begin
  inherited Create;
  FTree := ATree;
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

/// <summary>Parst ADocument als gemeinsamen Lauf; nil, wenn eine neuere Version ihn überholt hat.</summary>
function ParseShared(const ADocument: ITextDocument): IInterface;
var
  Run: TParseRun;
  Signal: IPascalCancellation;
  Previous: IPascalCancellation;
  Tree: TSyntaxTree;
begin
  Run := TParseRun.Create(ADocument.Version);
  Signal := Run;
  RunLock.Enter;
  try
    if not Running.TryGetValue(ADocument.Uri, Previous) then
      Running.Add(ADocument.Uri, Signal)
    else if (Previous as TParseRun).Version < ADocument.Version then
    begin
      (Previous as TParseRun).Cancel;
      Running[ADocument.Uri] := Signal;
    end;
    // Ist schon eine neuere Version in Arbeit, läuft dieser Parse ohne Eintrag zu Ende.
  finally
    RunLock.Leave;
  end;
  Tree := TPascalParser.Parse(ADocument.Text, Signal);
  TInterlocked.Increment(Parses);
  RunLock.Enter;
  try
    if Running.TryGetValue(ADocument.Uri, Previous) and (Previous = Signal) then
      Running.Remove(ADocument.Uri);
  finally
    RunLock.Leave;
  end;
  if Run.IsCancelled then
  begin
    Tree.Free;
    Exit(nil);
  end;
  Result := TSharedSyntaxTree.Create(Tree) as ISharedSyntaxTree;
end;

{ TSyntaxTreeCache }

class function TSyntaxTreeCache.Get(const ADocument: ITextDocument;
  const ACancellation: IPascalCancellation): ISharedSyntaxTree;
var
  Document: ITextDocument;
  Value: IInterface;
begin
  Document := ADocument;
  Value := Document.Derived(TreeKey,
    function: IInterface
    begin
      Result := ParseShared(Document);
    end);
  if Supports(Value, ISharedSyntaxTree, Result) then
    Exit;
  // Von einer neueren Version überholt: für diese (veraltete) Anfrage ohne Cache parsen.
  Result := TSharedSyntaxTree.Create(TPascalParser.Parse(Document.Text, ACancellation));
end;

class function TSyntaxTreeCache.Parse(const AText: string; const ACancellation: IPascalCancellation): TSyntaxTree;
begin
  Result := TPascalParser.Parse(AText, ACancellation);
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
  FreeAndNil(Running);
  FreeAndNil(RunLock);

end.
