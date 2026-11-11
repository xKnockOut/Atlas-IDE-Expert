unit Atlas.IDE.Assistants.FolderSignal;

// Änderungssignal eines Auftragsordners (#1984) über
// FindFirstChangeNotification: Changed fragt das Signal ohne Warten ab
// (WaitForSingleObject mit 0) und meldet neue, umbenannte oder gelöschte
// Dateien seit der letzten Abfrage. Kein Thread und keine Verzeichnisabfrage
// im Hauptthread; aufgelistet wird nur nach einem Signal (TAtlasInboxPace).
// Lässt sich der Ordner nicht beobachten, meldet Available False, und der
// Eingang verlässt sich auf das Sicherheitsnetz seines Takts.

interface

uses
  Winapi.Windows;

type
  TAtlasFolderSignal = class
  private
    FFolder: string;
    FHandle: THandle;
    procedure Open;
  public
    /// <summary>Legt AFolder bei Bedarf an und beobachtet ihn (ohne Unterordner).</summary>
    constructor Create(const AFolder: string);
    destructor Destroy; override;
    /// <summary>Dateinamen im Ordner haben sich seit der letzten Abfrage geändert; danach wieder scharf.</summary>
    function Changed: Boolean;
    /// <summary>Der Ordner wird beobachtet.</summary>
    function Available: Boolean;
    /// <summary>Beobachtung neu versuchen, wenn sie fehlt (Ordner war gelöscht oder nicht anzulegen).</summary>
    procedure Reopen;
  end;

implementation

uses
  System.SysUtils;

constructor TAtlasFolderSignal.Create(const AFolder: string);
begin
  inherited Create;
  FFolder := AFolder;
  FHandle := INVALID_HANDLE_VALUE;
  Open;
end;

destructor TAtlasFolderSignal.Destroy;
begin
  if Available then
  begin
    FindCloseChangeNotification(FHandle);
  end;
  FHandle := INVALID_HANDLE_VALUE;
  inherited Destroy;
end;

procedure TAtlasFolderSignal.Open;
begin
  if not ForceDirectories(FFolder) then
  begin
    Exit;
  end;
  FHandle := FindFirstChangeNotification(PChar(FFolder), False, FILE_NOTIFY_CHANGE_FILE_NAME);
end;

procedure TAtlasFolderSignal.Reopen;
begin
  if not Available then
  begin
    Open;
  end;
end;

function TAtlasFolderSignal.Available: Boolean;
begin
  Result := FHandle <> INVALID_HANDLE_VALUE;
end;

function TAtlasFolderSignal.Changed: Boolean;
begin
  Result := Available and (WaitForSingleObject(FHandle, 0) = WAIT_OBJECT_0);
  if Result and not FindNextChangeNotification(FHandle) then
  begin
    // Nicht wieder scharf zu machen (Ordner gelöscht): ab jetzt nur das Sicherheitsnetz.
    FindCloseChangeNotification(FHandle);
    FHandle := INVALID_HANDLE_VALUE;
  end;
end;

end.
