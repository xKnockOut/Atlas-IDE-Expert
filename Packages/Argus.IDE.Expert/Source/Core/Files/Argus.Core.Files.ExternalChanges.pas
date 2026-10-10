unit Argus.Core.Files.ExternalChanges;

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
  TArgusObservedFile = record
    FileName: string;
    Exists: Boolean;
    /// <summary>Zeitstempel auf der Platte (beliebige Einheit, nur Vergleich).</summary>
    Stamp: Int64;
    /// <summary>Puffer mit ungespeicherten Änderungen.</summary>
    Modified: Boolean;
    class function Create(const AFileName: string; AExists: Boolean; AStamp: Int64;
      AModified: Boolean): TArgusObservedFile; static;
  end;

  TArgusReloadAction = (Reload, KeepModified, Deleted);

  TArgusReloadDecision = record
    FileName: string;
    Action: TArgusReloadAction;
  end;

  TArgusExternalChanges = class
  public const
    QuietMs = 500;
  private type
    TKnown = record
      Exists: Boolean;
      Stamp: Int64;
    end;
  private
    FKnown: TDictionary<string, TKnown>;
    FPending: TDictionary<string, TArgusObservedFile>;
    FLastChange: Int64;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Aktueller Stand aller offenen Dateien; nicht mehr offene werden vergessen.</summary>
    procedure Observe(const AFiles: TArray<TArgusObservedFile>; ANowMs: Int64);
    /// <summary>Ein Vorgang ist fertig: Änderungen liegen vor und seit QuietMs kam keine dazu.</summary>
    function Due(ANowMs: Int64): Boolean;
    /// <summary>Entscheidungen für den fertigen Vorgang, nach Dateiname sortiert; der neue Stand gilt danach als bekannt.</summary>
    function TakeBatch: TArray<TArgusReloadDecision>;
    class function ActionText(AAction: TArgusReloadAction): string; static;
  end;

implementation

uses
  System.Generics.Defaults;

{ TArgusObservedFile }

class function TArgusObservedFile.Create(const AFileName: string; AExists: Boolean; AStamp: Int64;
  AModified: Boolean): TArgusObservedFile;
begin
  Result.FileName := AFileName;
  Result.Exists := AExists;
  Result.Stamp := AStamp;
  Result.Modified := AModified;
end;

{ TArgusExternalChanges }

class function TArgusExternalChanges.ActionText(AAction: TArgusReloadAction): string;
const
  Texts: array[TArgusReloadAction] of string = ('neu laden', 'ungespeicherte Änderungen, behalten', 'gelöscht');
begin
  Result := Texts[AAction];
end;

constructor TArgusExternalChanges.Create;
begin
  inherited Create;
  FKnown := TDictionary<string, TKnown>.Create;
  FPending := TDictionary<string, TArgusObservedFile>.Create;
end;

destructor TArgusExternalChanges.Destroy;
begin
  FPending.Free;
  FKnown.Free;
  inherited;
end;

procedure TArgusExternalChanges.Observe(const AFiles: TArray<TArgusObservedFile>; ANowMs: Int64);
var
  Observed: TArgusObservedFile;
  Known: TKnown;
  Open: TDictionary<string, Boolean>;
  Key: string;
  Pending: TArgusObservedFile;
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

function TArgusExternalChanges.Due(ANowMs: Int64): Boolean;
begin
  Result := (FPending.Count > 0) and (ANowMs - FLastChange >= QuietMs);
end;

function TArgusExternalChanges.TakeBatch: TArray<TArgusReloadDecision>;
var
  Observed: TArgusObservedFile;
  Known: TKnown;
  Decision: TArgusReloadDecision;
  List: TList<TArgusReloadDecision>;
begin
  List := TList<TArgusReloadDecision>.Create;
  try
    for Observed in FPending.Values do
    begin
      Decision.FileName := Observed.FileName;
      if not Observed.Exists then
        Decision.Action := TArgusReloadAction.Deleted
      else if Observed.Modified then
        Decision.Action := TArgusReloadAction.KeepModified
      else
        Decision.Action := TArgusReloadAction.Reload;
      List.Add(Decision);
      Known.Exists := Observed.Exists;
      Known.Stamp := Observed.Stamp;
      FKnown[UpperCase(Observed.FileName)] := Known;
    end;
    FPending.Clear;
    List.Sort(TComparer<TArgusReloadDecision>.Construct(
      function(const A, B: TArgusReloadDecision): Integer
      begin
        Result := CompareText(A.FileName, B.FileName);
      end));
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

end.