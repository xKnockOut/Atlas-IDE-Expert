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
  cTickMs = 200;

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
  Result := TAtlasIdeSettings.Current.Outline and not TAtlasGuard.Disabled(TAtlasFeature.Outline);
end;

{ TOutlineState }

constructor TOutlineState.Create;
begin
  inherited Create;
  FTimer := TTimer.Create(nil);
  FTimer.Interval := cTickMs;
  FTimer.OnTimer := Tick;
  FTimer.Enabled := True;
  TAtlasIdeOutlineWindow.OnFrame :=
    procedure(AFrame: TAtlasOutlineFrame)
    begin
      Wire(AFrame);
    end;
  // Das Fenster gab es schon (Paket neu geladen): neu verdrahten.
  if TAtlasIdeOutlineWindow.ExistingFrame <> nil then
  begin
    Wire(TAtlasIdeOutlineWindow.ExistingFrame);
  end;
end;

destructor TOutlineState.Destroy;
var
  mFrame: TAtlasOutlineFrame;
begin
  FTimer.Free;
  TAtlasIdeOutlineWindow.OnFrame := nil;
  mFrame := TAtlasIdeOutlineWindow.ExistingFrame;
  if mFrame <> nil then
  begin
    mFrame.OnOpen := nil;
    mFrame.OnSortChanged := nil;
    mFrame.OnFollowChanged := nil;
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
  AFrame.ShowConditions := TAtlasIdeSettings.Current.OutlineConditions;
  AFrame.OnOpen :=
    procedure(ANode: Integer; AImplementation: Boolean)
    begin
      TAtlasGuard.Run(TAtlasFeature.Outline,
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
  mFrame: TAtlasOutlineFrame;
  mTarget: Integer;
begin
  mFrame := TAtlasIdeOutlineWindow.ExistingFrame;
  if (mFrame = nil) or (ANode < 0) or (ANode > High(mFrame.Nodes)) or (FFileName = '') then
  begin
    Exit;
  end;
  mTarget := ANode;
  if AImplementation and (mFrame.Nodes[ANode].Body >= 0) then
  begin
    mTarget := mFrame.Nodes[ANode].Body;
  end;
  TAtlasIdeNavigation.GoToLocation(FFileName, mFrame.Nodes[mTarget].NameLine, mFrame.Nodes[mTarget].NameCharacter);
end;

procedure TOutlineState.Follow(const AView: IOTAEditView);
var
  mFrame: TAtlasOutlineFrame;
  mCursor: TOTAEditPos;
  mCharacter: Integer;
begin
  mFrame := TAtlasIdeOutlineWindow.ExistingFrame;
  if (mFrame = nil) or not mFrame.FollowCursor or (AView = nil) or (AView.Buffer = nil) then
  begin
    Exit;
  end;
  mCursor := AView.CursorPos;
  if mCursor.Line < 1 then
  begin
    Exit;
  end;
  mCharacter := TLspSession.ColumnToIndex(TAtlasEditorBuffer.LineText(AView, mCursor.Line), mCursor.Col,
    TAtlasEditorBuffer.TabWidth(AView.Buffer));
  if (mCursor.Line - 1 = FCursorLine) and (mCharacter = FCursorCharacter) then
  begin
    Exit;
  end;
  FCursorLine := mCursor.Line - 1;
  FCursorCharacter := mCharacter;
  mFrame.HighlightAt(FCursorLine, FCursorCharacter);
end;

procedure TOutlineState.Update;
var
  mFrame: TAtlasOutlineFrame;
  mView: IOTAEditView;
  mSnapshot: TAtlasOutlineSnapshot;
  mChanged: Boolean;
begin
  mFrame := TAtlasIdeOutlineWindow.ExistingFrame;
  if mFrame = nil then
  begin
    Exit;
  end;
  mView := TAtlasEditorBuffer.ActiveView;
  mSnapshot := TAtlasIdeOutlineCache.Refresh(mView);
  mChanged := not FShown or (mSnapshot.Status <> FStatus) or not SameText(mSnapshot.FileName, FFileName) or
    (mSnapshot.Stamp <> FStamp);
  if mChanged then
  begin
    FShown := True;
    FStatus := mSnapshot.Status;
    FFileName := mSnapshot.FileName;
    FStamp := mSnapshot.Stamp;
    FCursorLine := -1;
    case mSnapshot.Status of
      TAtlasOutlineStatus.NoFile:
        mFrame.SetMessage(TAtlasStrings.Text(TAtlasTextId.OutlineEmpty));
      TAtlasOutlineStatus.NoServer:
        mFrame.SetMessage(TAtlasStrings.Text(TAtlasTextId.OutlineNoServer));
      TAtlasOutlineStatus.Ready:
        mFrame.SetNodes(mSnapshot.Nodes);
    else
      // Übrige Werte bewusst ohne Wirkung.
    end;
  end;
  if mSnapshot.Status = TAtlasOutlineStatus.Ready then
  begin
    Follow(mView);
  end;
end;

procedure TOutlineState.Tick(Sender: TObject);
begin
  if not Active or not TAtlasIdeOutlineWindow.Visible then
  begin
    Exit;
  end;
  TAtlasGuard.Run(TAtlasFeature.Outline,
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
  mFrame: TAtlasOutlineFrame;
begin
  if (FState = nil) or not Active then
  begin
    Exit;
  end;
  mFrame := TAtlasIdeOutlineWindow.Show;
  if mFrame = nil then
  begin
    Exit;
  end;
  TOutlineState(FState).Reset;
  TOutlineState(FState).Update;
  if mFrame.Search.CanFocus then
  begin
    mFrame.Search.SetFocus;
  end;
end;

class procedure TAtlasIdeOutline.ApplySettings;
var
  mFrame: TAtlasOutlineFrame;
begin
  if FState = nil then
  begin
    Exit;
  end;
  if not Active then
  begin
    TAtlasIdeOutlineWindow.Hide;
    Exit;
  end;
  mFrame := TAtlasIdeOutlineWindow.ExistingFrame;
  if mFrame = nil then
  begin
    Exit;
  end;
  mFrame.Alphabetical := TAtlasIdeSettings.Current.OutlineAlphabetical;
  mFrame.FollowCursor := TAtlasIdeSettings.Current.OutlineFollowCursor;
  mFrame.ShowConditions := TAtlasIdeSettings.Current.OutlineConditions;
end;

class procedure TAtlasIdeOutline.ThemeChanged;
begin
  TAtlasIdeOutlineWindow.ApplyTheme;
end;

end.
