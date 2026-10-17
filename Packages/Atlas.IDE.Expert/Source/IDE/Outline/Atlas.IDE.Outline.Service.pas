unit Atlas.IDE.Outline.Service;

// Gliederungsfenster (#537) in der IDE:
// - Ein Zeitgeber folgt, solange das Fenster sichtbar ist, der aktiven
//   Quelltextdatei: Beim Dateiwechsel sofort, nach Änderungen erst nach einer
//   Tipppause gleicht er den Puffer mit dem Server ab und holt
//   textDocument/documentSymbol samt Atlas-Angaben (Sichtbarkeit, Marken,
//   nicht implementiert). Der Stand des Puffers kommt aus
//   TAtlasEditorSnapshots; der Text wird nur bei einer neuen Version gelesen.
// - Mit outline.followCursor hebt er den Eintrag am Cursor hervor, ohne zu
//   springen (im Rumpf einer Methode deren Deklaration).
// - Klick springt zur Deklaration, Doppelklick zur Implementierung (Rumpf in
//   derselben Unit; ohne Rumpf zur Deklaration).
// - Sortierknopf und „Cursor folgen“ schreiben outline.alphabetical bzw.
//   outline.followCursor; outline.enabled aus schließt das Fenster.
// Abgrenzung zur Strukturansicht der IDE: docs/Architektur.md.
// Nur im Hauptthread.

interface

uses
  System.SysUtils,
  Atlas.Core.Lsp.Session;

type
  TAtlasIdeOutline = class
  private class var
    FState: TObject;
  public
    class procedure Install(const ASessionOf: TFunc<TLspSession>); static;
    class procedure Uninstall; static;
    /// <summary>Fenster zeigen und füllen; nichts, solange outline.enabled aus ist.</summary>
    class procedure ShowWindow; static;
    class procedure ApplySettings; static;
    class procedure ThemeChanged; static;
  end;

implementation

uses
  Winapi.Windows,
  System.Classes,
  System.JSON,
  Vcl.ExtCtrls,
  ToolsAPI,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Outline.Model,
  Atlas.Core.Settings.Plugin,
  Atlas.UI.Strings,
  Atlas.UI.Outline.Frame,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.EditorSnapshot,
  Atlas.IDE.Foundation.Navigation,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Outline.Window;

const
  TickMs = 200;
  /// <summary>Tipppause, nach der die Gliederung neu geholt wird.</summary>
  PauseMs = 600;
  /// <summary>Ohne Server: so oft neu versuchen.</summary>
  RetryMs = 2000;
  RequestTimeoutMs = 2000;
  PascalExtensions: array[0..4] of string = ('.pas', '.dpr', '.dpk', '.inc', '.pp');

type
  TOutlineState = class
  private
    FSessionOf: TFunc<TLspSession>;
    FTimer: TTimer;
    FFileName: string;
    FVersion: Cardinal;
    FPendingVersion: Cardinal;
    FPendingSince: UInt64;
    /// <summary>Die Gliederung kam vom Server; sonst nach RetryMs neu versuchen.</summary>
    FLoaded: Boolean;
    FRetryAt: UInt64;
    FCursorLine: Integer;
    FCursorCharacter: Integer;
    procedure Tick(Sender: TObject);
    procedure Follow;
    procedure Load(const AView: IOTAEditView; const ASnapshot: TAtlasEditorSnapshot);
    procedure Wire(AFrame: TAtlasOutlineFrame);
    procedure Open(ANode: Integer; AImplementation: Boolean);
  public
    constructor Create(const ASessionOf: TFunc<TLspSession>);
    destructor Destroy; override;
    procedure Reset;
  end;

function IsPascal(const AFileName: string): Boolean;
var
  Extension: string;
begin
  for Extension in PascalExtensions do
    if SameText(ExtractFileExt(AFileName), Extension) then
      Exit(True);
  Result := False;
end;

function Active: Boolean;
begin
  Result := TAtlasIdeSettings.Current.Outline and not TAtlasGuard.Disabled(TAtlasFeature.EditorCommands);
end;

{ TOutlineState }

constructor TOutlineState.Create(const ASessionOf: TFunc<TLspSession>);
begin
  inherited Create;
  FSessionOf := ASessionOf;
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
  FVersion := 0;
  FPendingVersion := 0;
  FLoaded := False;
  FRetryAt := 0;
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

procedure TOutlineState.Load(const AView: IOTAEditView; const ASnapshot: TAtlasEditorSnapshot);
var
  Frame: TAtlasOutlineFrame;
  Session: TLspSession;
  Response: TJSONValue;
begin
  Frame := TAtlasIdeOutlineWindow.ExistingFrame;
  FFileName := AView.Buffer.FileName;
  FVersion := ASnapshot.Version;
  FPendingVersion := ASnapshot.Version;
  FCursorLine := -1;
  Session := nil;
  if Assigned(FSessionOf) then
    Session := FSessionOf();
  if Session = nil then
  begin
    FLoaded := False;
    FRetryAt := GetTickCount64 + RetryMs;
    Frame.SetMessage(TAtlasStrings.Text(TAtlasTextId.OutlineNoServer));
    Exit;
  end;
  Session.Sync(FFileName, ASnapshot.Text);
  Response := Session.DocumentSymbolTree(FFileName, RequestTimeoutMs);
  try
    FLoaded := Response <> nil;
    if not FLoaded then
    begin
      // Zeitgrenze oder Fehler: die alte Gliederung bleibt stehen, später neu versuchen.
      FRetryAt := GetTickCount64 + RetryMs;
      Exit;
    end;
    Frame.SetNodes(TAtlasOutline.FromJson(Response));
  finally
    Response.Free;
  end;
end;

procedure TOutlineState.Follow;
var
  Frame: TAtlasOutlineFrame;
  View: IOTAEditView;
  Cursor: TOTAEditPos;
  Character: Integer;
begin
  Frame := TAtlasIdeOutlineWindow.ExistingFrame;
  if (Frame = nil) or not Frame.FollowCursor then
    Exit;
  View := TAtlasEditorBuffer.ActiveView;
  if (View = nil) or (View.Buffer = nil) then
    Exit;
  Cursor := View.CursorPos;
  if Cursor.Line < 1 then
    Exit;
  Character := TLspSession.ColumnToIndex(TAtlasEditorBuffer.LineText(View, Cursor.Line), Cursor.Col,
    TAtlasEditorBuffer.TabWidth(View.Buffer));
  if (Cursor.Line - 1 = FCursorLine) and (Character = FCursorCharacter) then
    Exit;
  FCursorLine := Cursor.Line - 1;
  FCursorCharacter := Character;
  Frame.HighlightAt(FCursorLine, FCursorCharacter);
end;

procedure TOutlineState.Tick(Sender: TObject);
begin
  if not Active or not TAtlasIdeOutlineWindow.Visible or (TAtlasIdeOutlineWindow.ExistingFrame = nil) then
    Exit;
  TAtlasGuard.Run(TAtlasFeature.EditorCommands,
    procedure
    var
      View: IOTAEditView;
      Snapshot: TAtlasEditorSnapshot;
      Moment: UInt64;
    begin
      View := TAtlasEditorBuffer.ActiveView;
      if (View = nil) or (View.Buffer = nil) or not IsPascal(View.Buffer.FileName) then
      begin
        if FFileName <> '' then
        begin
          Reset;
          TAtlasIdeOutlineWindow.ExistingFrame.SetMessage(TAtlasStrings.Text(TAtlasTextId.OutlineEmpty));
        end;
        Exit;
      end;
      Snapshot := TAtlasEditorSnapshots.Get(View);
      Moment := GetTickCount64;
      if not SameText(View.Buffer.FileName, FFileName) then
        Load(View, Snapshot)
      else if Snapshot.Version <> FVersion then
      begin
        // Erst nach einer Tipppause neu holen.
        if Snapshot.Version <> FPendingVersion then
        begin
          FPendingVersion := Snapshot.Version;
          FPendingSince := Moment;
        end
        else if Moment - FPendingSince >= PauseMs then
          Load(View, Snapshot);
      end
      else if not FLoaded and (Moment >= FRetryAt) then
        Load(View, Snapshot);
      Follow;
    end);
end;

{ TAtlasIdeOutline }

class procedure TAtlasIdeOutline.Install(const ASessionOf: TFunc<TLspSession>);
begin
  FreeAndNil(FState);
  FState := TOutlineState.Create(ASessionOf);
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
  TOutlineState(FState).Tick(nil);
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
