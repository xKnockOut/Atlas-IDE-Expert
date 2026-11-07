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
    /// <summary>Entscheidungen für den fertigen Vorgang, nach Dateiname sortiert; der neue Stand gilt danach als
    /// bekannt.</summary>
    function TakeBatch: TArray<TAtlasReloadDecision>;
    class function ActionText(AAction: TAtlasReloadAction): string; static;
  end;

implementation

uses
  System.Generics.Defaults,
  Atlas.Core.Localization.Language;

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
  cTexts: array[TAtlasLanguage, TAtlasReloadAction] of string = (
    ('neu laden', 'ungespeicherte Änderungen, behalten', 'gelöscht'),
    ('reload', 'unsaved changes, kept', 'deleted'));
begin
  Result := cTexts[TAtlasTextLanguage.Current, AAction];
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
  mObserved: TAtlasObservedFile;
  mKnown: TKnown;
  mOpen: TDictionary<string, Boolean>;
  mKey: string;
  mPending: TAtlasObservedFile;
begin
  mOpen := TDictionary<string, Boolean>.Create;
  try
    for mObserved in AFiles do
    begin
      mKey := UpperCase(mObserved.FileName);
      mOpen.AddOrSetValue(mKey, True);
      if not FKnown.TryGetValue(mKey, mKnown) then
      begin
        // Neu geöffnet bzw. neue Datei ohne Platte: nur merken.
        mKnown.Exists := mObserved.Exists;
        mKnown.Stamp := mObserved.Stamp;
        FKnown.Add(mKey, mKnown);
        Continue;
      end;
      if (mKnown.Exists = mObserved.Exists) and (mKnown.Stamp = mObserved.Stamp) then
      begin
        FPending.Remove(mKey);
        Continue;
      end;
      // Noch nie auf der Platte gewesen (neue Unit): erstes Speichern ist keine externe Änderung.
      if not mKnown.Exists then
      begin
        mKnown.Exists := mObserved.Exists;
        mKnown.Stamp := mObserved.Stamp;
        FKnown[mKey] := mKnown;
        Continue;
      end;
      if not FPending.TryGetValue(mKey, mPending) or (mPending.Stamp <> mObserved.Stamp) or
        (mPending.Exists <> mObserved.Exists) then
      begin
        FLastChange := ANowMs;
      end;
      FPending.AddOrSetValue(mKey, mObserved);
    end;
    for mKey in FKnown.Keys.ToArray do
    begin
      if not mOpen.ContainsKey(mKey) then
      begin
        FKnown.Remove(mKey);
        FPending.Remove(mKey);
      end;
    end;
  finally
    mOpen.Free;
  end;
end;

function TAtlasExternalChanges.Due(ANowMs: Int64): Boolean;
begin
  Result := (FPending.Count > 0) and (ANowMs - FLastChange >= QuietMs);
end;

function TAtlasExternalChanges.TakeBatch: TArray<TAtlasReloadDecision>;
var
  mObserved: TAtlasObservedFile;
  mKnown: TKnown;
  mDecision: TAtlasReloadDecision;
  mList: TList<TAtlasReloadDecision>;
begin
  mList := TList<TAtlasReloadDecision>.Create;
  try
    for mObserved in FPending.Values do
    begin
      mDecision.FileName := mObserved.FileName;
      if not mObserved.Exists then
      begin
        mDecision.Action := TAtlasReloadAction.Deleted;
      end
      else if mObserved.Modified then
      begin
        mDecision.Action := TAtlasReloadAction.KeepModified;
      end
      else
      begin
        mDecision.Action := TAtlasReloadAction.Reload;
      end;
      mList.Add(mDecision);
      mKnown.Exists := mObserved.Exists;
      mKnown.Stamp := mObserved.Stamp;
      FKnown[UpperCase(mObserved.FileName)] := mKnown;
    end;
    FPending.Clear;
    mList.Sort(TComparer<TAtlasReloadDecision>.Construct(
      function(const A, B: TAtlasReloadDecision): Integer
      begin
        Result := CompareText(A.FileName, B.FileName);
      end));
    Result := mList.ToArray;
  finally
    mList.Free;
  end;
end;

end.