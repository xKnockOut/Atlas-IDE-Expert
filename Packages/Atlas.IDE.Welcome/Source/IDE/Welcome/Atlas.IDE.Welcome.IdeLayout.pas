unit Atlas.IDE.Welcome.IdeLayout;

// Layout der Willkommensseite der IDE (#753, #761, #1114) für die Steuerung
// (Atlas.IDE.Welcome.Commands):
// - Place sichert den Registry-Schlüssel WelcomePage der IDE nach
//   %LOCALAPPDATA%\Atlas\welcomepage-layout-backup.json (nur, wenn noch keine
//   Sicherung existiert) und setzt „Atlas“ oben über alle Spalten.
//   Unplace schreibt die Sicherung exakt zurück.
// - Retire nimmt Atlas von der Willkommensseite der IDE: Gibt es die
//   Sicherung, schreibt es sie zurück und löscht sie; sonst nimmt es seine
//   Kennungen aus dem Schlüssel.
// - Hält die IDE ihr Layout im Speicher und schreibt es beim Beenden zurück,
//   wiederholt CheckPending beim nächsten Start den gewünschten Stand (Marke
//   …-pending: "atlas" oder der Schlüssel als JSON).
// Abgeteilt aus Atlas.IDE.Welcome.Commands (Atlas-Befunde).

interface

uses
  System.SysUtils,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Welcome.Backup;

type
  TAtlasIdeWelcomeIdeLayout = class
  private
    FAccess: IAtlasRegistryAccess;
    FMessage: TProc<string>;
    function WelcomeKey: string;
    function BoardPlaced: Boolean;
    function PlaceBoard: Boolean;
  public
    /// <summary>AMessage: Zeile in die Meldungsansicht.</summary>
    constructor Create(const AMessage: TProc<string>);
    /// <summary>Sollen nach den Einstellungen Atlas-Bereiche auf der Willkommensseite der IDE stehen?</summary>
    class function Wanted(const ASettings: TAtlasPluginSettings): Boolean; static;
    /// <summary>Gewünschten Stand aus der Marke wiederholen, falls die IDE ihn beim Beenden überschrieben hat.
    /// </summary>
    procedure CheckPending;
    /// <summary>Atlas-Bereiche von der Willkommensseite der IDE nehmen; meldet sich nur, wenn es etwas zu tun gab.
    /// </summary>
    procedure Retire;
    /// <summary>Marke des gewünschten Stands löschen.</summary>
    procedure ClearPending;
    /// <summary>Sichern und „Atlas“ oben platzieren; False, wenn es keine Willkommensseite gibt oder die Sicherung
    /// scheitert. AReport: Erfolg melden.</summary>
    function Place(AReport: Boolean): Boolean;
    /// <summary>Gesicherten Stand zurückschreiben; False ohne Sicherung (mit AReport gemeldet).</summary>
    function Unplace(AReport: Boolean): Boolean;
    /// <summary>Wird für Tests ersetzt; Vorgabe: Registry der IDE.</summary>
    property Access: IAtlasRegistryAccess read FAccess write FAccess;
  end;

implementation

uses
  System.IOUtils,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Files.DataFile,
  Atlas.Core.Welcome.HostLayout,
  Atlas.Core.Welcome.Sections,
  Atlas.UI.Welcome.Strings,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Welcome.Registry,
  Atlas.IDE.Welcome.Page;

function AtlasFolder: string;
begin
  Result := TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'Atlas');
end;

function PendingFile: string;
begin
  Result := TPath.Combine(AtlasFolder, 'welcomepage-layout-pending');
end;

/// <summary>Textdatei lesen, mit oder ohne Byte-Order-Mark (frühere Fassungen schrieben eines); teilt Löschen,
/// damit es das atomare Ersetzen nicht blockiert. EInOutError, wenn sie nicht lesbar ist.</summary>
function ReadText(const AFileName: string): string;
begin
  if not TAtlasDataFile.TryRead(AFileName, Result) then
  begin
    raise EInOutError.Create('Datei der Willkommensseite nicht lesbar');
  end;
end;

function BoardId: string;
begin
  Result := TAtlasWelcomeIds.PluginId(TAtlasWelcomeIds.cBoard);
end;

{ TAtlasIdeWelcomeIdeLayout }

constructor TAtlasIdeWelcomeIdeLayout.Create(const AMessage: TProc<string>);
begin
  inherited Create;
  FMessage := AMessage;
  FAccess := TAtlasIdeRegistryAccess.Create;
end;

class function TAtlasIdeWelcomeIdeLayout.Wanted(const ASettings: TAtlasPluginSettings): Boolean;
begin
  Result := ASettings.WelcomePage and ASettings.WelcomePageIdePage;
end;

function TAtlasIdeWelcomeIdeLayout.WelcomeKey: string;
begin
  Result := TAtlasWelcomeBackup.WelcomeKey(TAtlasIdeRegistryAccess.IdeBaseKey);
end;

function TAtlasIdeWelcomeIdeLayout.BoardPlaced: Boolean;
var
  mKey: TAtlasRegKey;
  mLayout: TAtlasHostLayout;
begin
  mKey := FAccess.Read(WelcomeKey);
  try
    Result := (mKey <> nil) and TAtlasHostLayout.Read(mKey, mLayout) and
      mLayout.HasAtlasOnTop(BoardId, TAtlasWelcomeIds.cPluginPrefix);
  finally
    mKey.Free;
  end;
end;

function TAtlasIdeWelcomeIdeLayout.PlaceBoard: Boolean;
var
  mKey: TAtlasRegKey;
  mLayout: TAtlasHostLayout;
begin
  mKey := FAccess.Read(WelcomeKey);
  try
    if mKey = nil then
    begin
      mKey := TAtlasRegKey.Create('WelcomePage');
    end;
    // Ohne Raster in der Registry zeigt die IDE ihre Vorgabe; von der gehen wir aus.
    if not TAtlasHostLayout.Read(mKey, mLayout) then
    begin
      mLayout := TAtlasHostLayout.IdeDefault;
    end;
    Result := not mLayout.HasAtlasOnTop(BoardId, TAtlasWelcomeIds.cPluginPrefix);
    if Result then
    begin
      mLayout.WithAtlasOnTop(BoardId, TAtlasWelcomeIds.cPluginPrefix).WriteTo(mKey);
      FAccess.Replace(WelcomeKey, mKey);
    end;
  finally
    mKey.Free;
  end;
end;

procedure TAtlasIdeWelcomeIdeLayout.ClearPending;
begin
  System.SysUtils.DeleteFile(PendingFile);
end;

procedure TAtlasIdeWelcomeIdeLayout.CheckPending;
begin
  // Die Marke enthält den gewünschten Stand: "atlas" oder den Schlüssel WelcomePage, der gelten soll. Hat die
  // IDE ihr Layout beim Beenden aus dem Speicher zurückgeschrieben, wird der Stand hier wiederholt; gilt er beim
  // Start schon, hat die IDE ihn übernommen und die Marke entfällt.
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    var
      mWanted: string;
      mCurrent: TAtlasPluginSettings;
      mDone: Boolean;
    begin
      if not FileExists(PendingFile) then
      begin
        Exit;
      end;
      mWanted := Trim(ReadText(PendingFile));
      mCurrent := TAtlasIdeSettings.Current;
      if mWanted = 'atlas' then
      begin
        mDone := not Wanted(mCurrent) or not SameText(mCurrent.WelcomePageLayout, 'atlas') or BoardPlaced;
        if not mDone then
        begin
          PlaceBoard;
        end;
      end
      else
      begin
        mDone := TAtlasWelcomeBackup.Matches(FAccess, mWanted) or not TAtlasWelcomeBackup.Restore(FAccess, mWanted);
      end;
      if mDone then
      begin
        ClearPending;
      end;
    end);
end;

procedure TAtlasIdeWelcomeIdeLayout.Retire;
begin
  // Danach ist die Sicherung verbraucht: „Atlas-Layout anwenden“ sichert beim nächsten Mal neu.
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    var
      mBackup, mSaved, mSnapshot: string;
      mOutcome: TAtlasRetireResult;
    begin
      mBackup := TAtlasWelcomeBackup.BackupFile(AtlasFolder);
      mSaved := '';
      if FileExists(mBackup) then
      begin
        mSaved := ReadText(mBackup);
      end;
      mOutcome := TAtlasWelcomeRetire.Run(FAccess, WelcomeKey, mSaved, TAtlasWelcomeIds.cPluginPrefix, mSnapshot);
      // Die Sicherung hat ausgedient, auch wenn sie nicht mehr lesbar war.
      if FileExists(mBackup) then
      begin
        System.SysUtils.DeleteFile(mBackup);
      end;
      if mOutcome = TAtlasRetireResult.Nothing then
      begin
        Exit;
      end;
      TAtlasDataFile.Write(PendingFile, mSnapshot);
      if Assigned(FMessage) then
      begin
        FMessage(TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeRetired));
      end;
    end);
end;

function TAtlasIdeWelcomeIdeLayout.Place(AReport: Boolean): Boolean;
var
  mBackup: string;
begin
  Result := False;
  if not TAtlasIdeWelcomePage.Available then
  begin
    Exit;
  end;
  mBackup := TAtlasWelcomeBackup.BackupFile(AtlasFolder);
  // Nur die erste Sicherung zählt: Sie hält das Layout vor Atlas.
  if not FileExists(mBackup) then
  begin
    try
      // Atomar (Bericht N3): Eine halb geschriebene Sicherung verlöre das Layout vor Atlas für immer.
      TAtlasDataFile.Write(mBackup, TAtlasWelcomeBackup.Snapshot(FAccess, WelcomeKey));
    except
      on E: Exception do
      begin
        if Assigned(FMessage) then
        begin
          FMessage(TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeBackupFailed, [E.Message]));
        end;
        Exit;
      end;
    end;
  end;
  PlaceBoard;
  TAtlasDataFile.Write(PendingFile, 'atlas');
  Result := True;
  if AReport and Assigned(FMessage) then
  begin
    FMessage(TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeApplied));
  end;
end;

function TAtlasIdeWelcomeIdeLayout.Unplace(AReport: Boolean): Boolean;
var
  mBackup, mSnapshot: string;
begin
  Result := False;
  mSnapshot := '';
  mBackup := TAtlasWelcomeBackup.BackupFile(AtlasFolder);
  if FileExists(mBackup) then
  begin
    mSnapshot := ReadText(mBackup);
    Result := TAtlasWelcomeBackup.Restore(FAccess, mSnapshot);
  end;
  if not Result then
  begin
    if AReport and Assigned(FMessage) then
    begin
      FMessage(TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeNoBackup));
    end;
    Exit;
  end;
  // Bis die IDE den Stand übernommen hat, gilt die Sicherung als gewünschter Stand (CheckPending).
  TAtlasDataFile.Write(PendingFile, mSnapshot);
  System.SysUtils.DeleteFile(mBackup);
  if AReport and Assigned(FMessage) then
  begin
    FMessage(TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeResetDone));
  end;
end;

end.
