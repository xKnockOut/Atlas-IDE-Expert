unit Atlas.IDE.Outline.Service;

// Gliederungsfenster (#537) in der IDE:
// - Ein Zeitgeber folgt, solange das Fenster sichtbar ist, der aktiven
//   Quelltextdatei. Den Stand der Gliederung liefert TAtlasIdeOutlineCache
//   (gemeinsam mit der Brotkrumenleiste #590): beim Dateiwechsel sofort, nach
//   Änderungen erst nach einer Tipppause.
// - Mit outline.followCursor hebt er den Eintrag am Cursor hervor, ohne zu
//   springen (im Rumpf einer Methode deren Deklaration).
// - Klick springt zur Deklaration, Doppelklick zur Implementierung (Rumpf in
//   derselben Unit; ohne Rumpf zur Deklaration).
// - Sortierknopf und „Cursor folgen“ schreiben outline.alphabetical bzw.
//   outline.followCursor; outline.enabled aus schließt das Fenster.
// Abgrenzung zur Strukturansicht der IDE: docs/Architektur.md.
// Nur im Hauptthread.

interface

type
  TAtlasIdeOutline = class
  private class var
    FState: TObject;
  public
    /// <summary>Den Server fragt TAtlasIdeOutlineCache (vorher installieren).</summary>
    class procedure Install; static;
    class procedure Uninstall; static;
    /// <summary>Fenster zeigen und füllen; nichts, solange outline.enabled aus ist.</summary>
    class procedure ShowWindow; static;
    class procedure ApplySettings; static;
    class procedure ThemeChanged; static;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  Vcl.ExtCtrls,
  ToolsAPI,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Outline.Model,
  Atlas.Core.Settings.Plugin,
  Atlas.UI.Strings,
  Atlas.UI.Outline.Frame,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.Navigation,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Outline.Cache,
  Atlas.IDE.Outline.Window;

const
  TickMs = 200;

type
  TOutlineState = class
  private
    FTimer: TTimer;
    FFileName: string;
    FStamp: Cardinal;
    FStatus: TAtlasOutlineStatus;
    FShown: Boolean;
    FCursorLine: Integer;
    FCursorCharacter: Integer;
    procedure Tick(Sender: TObject);
    procedure Follow(const AView: IOTAEditView);
    procedure Wire(AFrame: TAtlasOutlineFrame);
    procedure Open(ANode: Integer; AImplementation: Boolean);
  public
    constructor Create;
    destructor Destroy; override;
    procedure Reset;
    procedure Update;
  end;

function Active: Boolean;
begin
  Result := TAtlasIdeSettings.Current.Outline and not TAtlasGuard.Disabled(TAtlasFeature.EditorCommands);
end;

{ TOutlineState }

constructor TOutlineState.Create;
begin
  inherited Create;
  FTimer := TTimer.Create(nil);
  FTimer.Interval := TickMs;
  FTimer.OnTimer := Tick;
  FTimer.Enabled := True;
  TAtlasIdeOutlineWindow.OnFrame :=
    procedure(AFrame: TAtlasOutlineFrame)
    begin
      Wire(AFrame);
    end;
  // Das Fenster gab es schon (Paket neu geladen): neu verdrahten.
  if TAtlasIdeOutlineWindow.ExistingFrame <> nil then
    Wire(TAtlasIdeOutlineWindow.ExistingFrame);
end;

destructor TOutlineState.Destroy;
var
  Frame: TAtlasOutlineFrame;
begin
  FTimer.Free;
  TAtlasIdeOutlineWindow.OnFrame := nil;
  Frame := TAtlasIdeOutlineWindow.ExistingFrame;
  if Frame <> nil then
  begin
    Frame.OnOpen := nil;
    Frame.OnSortChanged := nil;
    Frame.OnFollowChanged := nil;
  end;
  inherited Destroy;
end;

procedure TOutlineState.Reset;
begin
  FFileName := '';
  FStamp := 0;
  FShown := False;
  FCursorLine := -1;
  FCursorCharacter := -1;
end;

procedure TOutlineState.Wire(AFrame: TAtlasOutlineFrame);
begin
  AFrame.Alphabetical := TAtlasIdeSettings.Current.OutlineAlphabetical;
  AFrame.FollowCursor := TAtlasIdeSettings.Current.OutlineFollowCursor;
  AFrame.OnOpen :=
    procedure(ANode: Integer; AImplementation: Boolean)
    begin
      TAtlasGuard.Run(TAtlasFeature.EditorCommands,
        procedure
        begin
          Open(ANode, AImplementation);
        end);
    end;
  AFrame.OnSortChanged :=
    procedure(AValue: Boolean)
    var
      Next: TAtlasPluginSettings;
    begin
      Next := TAtlasIdeSettings.Stored;
      Next.OutlineAlphabetical := AValue;
      TAtlasIdeSettings.Update(Next);
    end;
  AFrame.OnFollowChanged :=
    procedure(AValue: Boolean)
    var
      Next: TAtlasPluginSettings;
    begin
      Next := TAtlasIdeSettings.Stored;
      Next.OutlineFollowCursor := AValue;
      TAtlasIdeSettings.Update(Next);
    end;
  Reset;
end;

procedure TOutlineState.Open(ANode: Integer; AImplementation: Boolean);
var
  Frame: TAtlasOutlineFrame;
  Target: Integer;
begin
  Frame := TAtlasIdeOutlineWindow.ExistingFrame;
  if (Frame = nil) or (ANode < 0) or (ANode > High(Frame.Nodes)) or (FFileName = '') then
    Exit;
  Target := ANode;
  if AImplementation and (Frame.Nodes[ANode].Body >= 0) then
    Target := Frame.Nodes[ANode].Body;
  TAtlasIdeNavigation.GoToLocation(FFileName, Frame.Nodes[Target].NameLine, Frame.Nodes[Target].NameCharacter);
end;

procedure TOutlineState.Follow(const AView: IOTAEditView);
var
  Frame: TAtlasOutlineFrame;
  Cursor: TOTAEditPos;
  Character: Integer;
begin
  Frame := TAtlasIdeOutlineWindow.ExistingFrame;
  if (Frame = nil) or not Frame.FollowCursor or (AView = nil) or (AView.Buffer = nil) then
    Exit;
  Cursor := AView.CursorPos;
  if Cursor.Line < 1 then
    Exit;
  Character := TLspSession.ColumnToIndex(TAtlasEditorBuffer.LineText(AView, Cursor.Line), Cursor.Col,
    TAtlasEditorBuffer.TabWidth(AView.Buffer));
  if (Cursor.Line - 1 = FCursorLine) and (Character = FCursorCharacter) then
    Exit;
  FCursorLine := Cursor.Line - 1;
  FCursorCharacter := Character;
  Frame.HighlightAt(FCursorLine, FCursorCharacter);
end;

procedure TOutlineState.Update;
var
  Frame: TAtlasOutlineFrame;
  View: IOTAEditView;
  Snapshot: TAtlasOutlineSnapshot;
  Changed: Boolean;
begin
  Frame := TAtlasIdeOutlineWindow.ExistingFrame;
  if Frame = nil then
    Exit;
  View := TAtlasEditorBuffer.ActiveView;
  Snapshot := TAtlasIdeOutlineCache.Refresh(View);
  Changed := not FShown or (Snapshot.Status <> FStatus) or not SameText(Snapshot.FileName, FFileName) or
    (Snapshot.Stamp <> FStamp);
  if Changed then
  begin
    FShown := True;
    FStatus := Snapshot.Status;
    FFileName := Snapshot.FileName;
    FStamp := Snapshot.Stamp;
    FCursorLine := -1;
    case Snapshot.Status of
      TAtlasOutlineStatus.NoFile:
        Frame.SetMessage(TAtlasStrings.Text(TAtlasTextId.OutlineEmpty));
      TAtlasOutlineStatus.NoServer:
        Frame.SetMessage(TAtlasStrings.Text(TAtlasTextId.OutlineNoServer));
      TAtlasOutlineStatus.Ready:
        Frame.SetNodes(Snapshot.Nodes);
    end;
  end;
  if Snapshot.Status = TAtlasOutlineStatus.Ready then
    Follow(View);
end;

procedure TOutlineState.Tick(Sender: TObject);
begin
  if not Active or not TAtlasIdeOutlineWindow.Visible then
    Exit;
  TAtlasGuard.Run(TAtlasFeature.EditorCommands,
    procedure
    begin
      Update;
    end);
end;

{ TAtlasIdeOutline }

class procedure TAtlasIdeOutline.Install;
begin
  FreeAndNil(FState);
  FState := TOutlineState.Create;
end;

class procedure TAtlasIdeOutline.Uninstall;
begin
  FreeAndNil(FState);
  TAtlasIdeOutlineWindow.Release;
end;

class procedure TAtlasIdeOutline.ShowWindow;
var
  Frame: TAtlasOutlineFrame;
begin
  if (FState = nil) or not Active then
    Exit;
  Frame := TAtlasIdeOutlineWindow.Show;
  if Frame = nil then
    Exit;
  TOutlineState(FState).Reset;
  TOutlineState(FState).Update;
  if Frame.Search.CanFocus then
    Frame.Search.SetFocus;
end;

class procedure TAtlasIdeOutline.ApplySettings;
var
  Frame: TAtlasOutlineFrame;
begin
  if FState = nil then
    Exit;
  if not Active then
  begin
    TAtlasIdeOutlineWindow.Hide;
    Exit;
  end;
  Frame := TAtlasIdeOutlineWindow.ExistingFrame;
  if Frame = nil then
    Exit;
  Frame.Alphabetical := TAtlasIdeSettings.Current.OutlineAlphabetical;
  Frame.FollowCursor := TAtlasIdeSettings.Current.OutlineFollowCursor;
end;

class procedure TAtlasIdeOutline.ThemeChanged;
begin
  TAtlasIdeOutlineWindow.ApplyTheme;
end;

end.
