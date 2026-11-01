unit Atlas.Core.Files.ExternalChanges;

// Extern geänderte Dateien (#536), ohne Open Tools API: Die IDE-Schicht
// meldet regelmäßig die offenen Dateien mit Zeitstempel auf der Platte und
// ob ihr Puffer ungespeicherte Änderungen hat. Änderungen werden gebündelt:
// Erst wenn 500 ms lang keine weitere dazukam, gilt der Vorgang als fertig
// (git checkout ändert viele Dateien kurz nacheinander).
// Entscheidung je Datei: ohne eigene Änderungen still neu laden, mit eigenen
// Änderungen nicht anfassen (die IDE fragt), gelöscht nur melden.
// Der erste Blick auf eine Datei merkt sich nur ihren Stand.

interface

{$SCOPEDENUMS ON}

uses
  System.SysUtils,
  System.Generics.Collections;

type
  TAtlasObservedFile = record
    FileName: string;
    Exists: Boolean;
    /// <summary>Zeitstempel auf der Platte (beliebige Einheit, nur Vergleich).</summary>
    Stamp: Int64;
    /// <summary>Puffer mit ungespeicherten Änderungen.</summary>
    Modified: Boolean;
    class function Create(const AFileName: string; AExists: Boolean; AStamp: Int64;
      AModified: Boolean): TAtlasObservedFile; static;
  end;

  TAtlasReloadAction = (Reload, KeepModified, Deleted);

  TAtlasReloadDecision = record
    FileName: string;
    Action: TAtlasReloadAction;
  end;

  TAtlasExternalChanges = class
  public const
    QuietMs = 500;
  private type
    TKnown = record
      Exists: Boolean;
      Stamp: Int64;
    end;
  private
    FKnown: TDictionary<string, TKnown>;
    FPending: TDictionary<string, TAtlasObservedFile>;
    FLastChange: Int64;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Aktueller Stand aller offenen Dateien; nicht mehr offene werden vergessen.</summary>
    procedure Observe(const AFiles: TArray<TAtlasObservedFile>; ANowMs: Int64);
    /// <summary>Ein Vorgang ist fertig: Änderungen liegen vor und seit QuietMs kam keine dazu.</summary>
    function Due(ANowMs: Int64): Boolean;
    /// <summary>Entscheidungen für den fertigen Vorgang, nach Dateiname sortiert; der neue Stand gilt danach als bekannt.</summary>
    function TakeBatch: TArray<TAtlasReloadDecision>;
    class function ActionText(AAction: TAtlasReloadAction): string; static;
  end;

implementation

uses
  System.Generics.Defaults;

{ TAtlasObservedFile }

class function TAtlasObservedFile.Create(const AFileName: string; AExists: Boolean; AStamp: Int64;
  AModified: Boolean): TAtlasObservedFile;
begin
  Result.FileName := AFileName;
  Result.Exists := AExists;
  Result.Stamp := AStamp;
  Result.Modified := AModified;
end;

{ TAtlasExternalChanges }

class function TAtlasExternalChanges.ActionText(AAction: TAtlasReloadAction): string;
const
  Texts: array[TAtlasReloadAction] of string = ('neu laden', 'ungespeicherte Änderungen, behalten', 'gelöscht');
begin
  Result := Texts[AAction];
end;

constructor TAtlasExternalChanges.Create;
begin
  inherited Create;
  FKnown := TDictionary<string, TKnown>.Create;
  FPending := TDictionary<string, TAtlasObservedFile>.Create;
end;

destructor TAtlasExternalChanges.Destroy;
begin
  FPending.Free;
  FKnown.Free;
  inherited;
end;

procedure TAtlasExternalChanges.Observe(const AFiles: TArray<TAtlasObservedFile>; ANowMs: Int64);
var
  Observed: TAtlasObservedFile;
  Known: TKnown;
  Open: TDictionary<string, Boolean>;
  Key: string;
  Pending: TAtlasObservedFile;
begin
  Open := TDictionary<string, Boolean>.Create;
  try
    for Observed in AFiles do
    begin
      Key := UpperCase(Observed.FileName);
      Open.AddOrSetValue(Key, True);
      if not FKnown.TryGetValue(Key, Known) then
      begin
        // Neu geöffnet bzw. neue Datei ohne Platte: nur merken.
        Known.Exists := Observed.Exists;
        Known.Stamp := Observed.Stamp;
        FKnown.Add(Key, Known);
        Continue;
      end;
      if (Known.Exists = Observed.Exists) and (Known.Stamp = Observed.Stamp) then
      begin
        FPending.Remove(Key);
        Continue;
      end;
      // Noch nie auf der Platte gewesen (neue Unit): erstes Speichern ist keine externe Änderung.
      if not Known.Exists then
      begin
        Known.Exists := Observed.Exists;
        Known.Stamp := Observed.Stamp;
        FKnown[Key] := Known;
        Continue;
      end;
      if not FPending.TryGetValue(Key, Pending) or (Pending.Stamp <> Observed.Stamp) or
        (Pending.Exists <> Observed.Exists) then
        FLastChange := ANowMs;
      FPending.AddOrSetValue(Key, Observed);
    end;
    for Key in FKnown.Keys.ToArray do
      if not Open.ContainsKey(Key) then
      begin
        FKnown.Remove(Key);
        FPending.Remove(Key);
      end;
  finally
    Open.Free;
  end;
end;

function TAtlasExternalChanges.Due(ANowMs: Int64): Boolean;
begin
  Result := (FPending.Count > 0) and (ANowMs - FLastChange >= QuietMs);
end;

function TAtlasExternalChanges.TakeBatch: TArray<TAtlasReloadDecision>;
var
  Observed: TAtlasObservedFile;
  Known: TKnown;
  Decision: TAtlasReloadDecision;
  List: TList<TAtlasReloadDecision>;
begin
  List := TList<TAtlasReloadDecision>.Create;
  try
    for Observed in FPending.Values do
    begin
      Decision.FileName := Observed.FileName;
      if not Observed.Exists then
        Decision.Action := TAtlasReloadAction.Deleted
      else if Observed.Modified then
        Decision.Action := TAtlasReloadAction.KeepModified
      else
        Decision.Action := TAtlasReloadAction.Reload;
      List.Add(Decision);
      Known.Exists := Observed.Exists;
      Known.Stamp := Observed.Stamp;
      FKnown[UpperCase(Observed.FileName)] := Known;
    end;
    FPending.Clear;
    List.Sort(TComparer<TAtlasReloadDecision>.Construct(
      function(const A, B: TAtlasReloadDecision): Integer
      begin
        Result := CompareText(A.FileName, B.FileName);
      end));
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

end.