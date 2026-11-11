unit Atlas.IDE.Designer.HandleTool;

// Gemeinsamer Teil der Werkzeuge mit Griffen über dem Designer (#734
// Abstandsgriffe, #737 gemeinsame Größengriffe) in der IDE:
// - Ein- und Ausschalten über das Symbol des Knopfs (Active), Menü am Pfeil
//   mit „… zeigen“, den Befehlen des Werkzeugs und „… rückgängig“.
// - Griff-Fenster TAtlasDesignerHandles; Maus und Doppelklick gehen an die
//   abgeleitete Klasse (Down, Drag, Up, DoubleClick), jeweils unter dem
//   Wächter der Designer-Leiste.
// - Schritte: BeginStep merkt den Stand (TAtlasDesignerSnapshot), ein
//   Schritt mit Änderung (Changed) wird bei CommitStep zum Stand für
//   „… rückgängig“, sonst verworfen.
// Nur im Hauptthread.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  Vcl.Menus,
  Atlas.UI.Designer.Handles,
  Atlas.IDE.Designer.Snapshot;

type
  TAtlasIdeHandleTool = class
  private
    FOnMessage: TProc<string>;
    FActive: Boolean;
    FMenu: TPopupMenu;
    FOverlay: TAtlasDesignerHandles;
    FUndo: TAtlasDesignerSnapshot;
    FStep: TAtlasDesignerSnapshot;
    FChanged: Boolean;
    procedure MenuClick(Sender: TObject);
    procedure RunGuarded(const AAction: TProc);
  protected
    procedure Say(const AText: string);
    /// <summary>Griff-Fenster anlegen und verdrahten.</summary>
    procedure EnsureOverlay;
    procedure Down(AIndex: Integer; AShift: TShiftState); virtual; abstract;
    procedure Drag(const ADelta: TPoint; AShift: TShiftState); virtual; abstract;
    procedure Up; virtual; abstract;
    procedure DoubleClick(AIndex: Integer; AShift: TShiftState); virtual;
    /// <summary>Befehle zwischen „… zeigen“ und „… rückgängig“ (Beschriftungen); Klick: Command.</summary>
    function Commands: TArray<string>; virtual;
    function CommandEnabled(AIndex: Integer): Boolean; virtual;
    procedure Command(AIndex: Integer); virtual;
    function ShowCaption: string; virtual; abstract;
    function UndoCaption: string; virtual; abstract;
    function UndoneText: string; virtual; abstract;
    /// <summary>Stand vor einem Schritt merken.</summary>
    procedure BeginStep;
    /// <summary>Schritt beenden: mit Änderung als Stand für „rückgängig“ (Designer geändert, ADone in die
    /// Meldungen), ohne verwerfen. ARestore: Stand vor dem Schritt wiederherstellen.</summary>
    procedure CommitStep(const ADone: string; ARestore: Boolean = False);
    function InStep: Boolean;
    property Overlay: TAtlasDesignerHandles read FOverlay;
    property Changed: Boolean read FChanged write FChanged;
  public
    /// <summary>AOnMessage: Zeile in der Meldungsansicht.</summary>
    constructor Create(const AOnMessage: TProc<string>);
    destructor Destroy; override;
    /// <summary>Klick auf das Symbol: Griffe ein- oder ausblenden.</summary>
    procedure Toggle;
    /// <summary>Menü am Pfeil an APoint (Bildschirm).</summary>
    procedure Popup(const APoint: TPoint);
    /// <summary>Takt der Leiste: Griffe der Auswahl folgen.</summary>
    procedure Tick; virtual; abstract;
    procedure Hide; virtual;
    procedure ApplyTheme;
    function Dragging: Boolean;
    property Active: Boolean read FActive;
  end;

implementation

uses
  Vcl.Forms,
  ToolsAPI,
  Atlas.Core.Diagnostics.Guard,
  Atlas.IDE.Designer.Access,
  Atlas.IDE.Foundation.EditorStyle;

{ TAtlasIdeHandleTool }

constructor TAtlasIdeHandleTool.Create(const AOnMessage: TProc<string>);
begin
  inherited Create;
  FOnMessage := AOnMessage;
  FActive := True;
  FMenu := TPopupMenu.Create(nil);
  FUndo := TAtlasDesignerSnapshot.Create;
end;

destructor TAtlasIdeHandleTool.Destroy;
begin
  FOverlay.Free;
  FStep.Free;
  FUndo.Free;
  FMenu.Free;
  inherited Destroy;
end;

procedure TAtlasIdeHandleTool.Say(const AText: string);
begin
  if Assigned(FOnMessage) then
  begin
    FOnMessage(AText);
  end;
end;

procedure TAtlasIdeHandleTool.RunGuarded(const AAction: TProc);
begin
  TAtlasGuard.Run(TAtlasFeature.DesignerBar, AAction);
end;

procedure TAtlasIdeHandleTool.DoubleClick(AIndex: Integer; AShift: TShiftState);
begin
  // Ohne Doppelklick-Befehl.
end;

function TAtlasIdeHandleTool.Commands: TArray<string>;
begin
  Result := nil;
end;

function TAtlasIdeHandleTool.CommandEnabled(AIndex: Integer): Boolean;
begin
  Result := True;
end;

procedure TAtlasIdeHandleTool.Command(AIndex: Integer);
begin
  // Ohne eigene Befehle.
end;

procedure TAtlasIdeHandleTool.EnsureOverlay;
var
  mOwner: TAtlasIdeHandleTool;
begin
  if FOverlay <> nil then
  begin
    Exit;
  end;
  mOwner := Self;
  FOverlay := TAtlasDesignerHandles.CreateHandles(nil, Application.MainFormHandle, TAtlasIdeStyle.Colors);
  FOverlay.OnDown :=
    procedure(AIndex: Integer; AShift: TShiftState)
    var
      mIndex: Integer;
      mShift: TShiftState;
    begin
      mIndex := AIndex;
      mShift := AShift;
      mOwner.RunGuarded(
        procedure
        begin
          mOwner.Down(mIndex, mShift);
        end);
    end;
  FOverlay.OnDrag :=
    procedure(ADelta: TPoint; AShift: TShiftState)
    var
      mDelta: TPoint;
      mShift: TShiftState;
    begin
      mDelta := ADelta;
      mShift := AShift;
      mOwner.RunGuarded(
        procedure
        begin
          mOwner.Drag(mDelta, mShift);
        end);
    end;
  FOverlay.OnUp :=
    procedure(AShift: TShiftState)
    begin
      mOwner.RunGuarded(
        procedure
        begin
          mOwner.Up;
        end);
    end;
  FOverlay.OnDoubleClick :=
    procedure(AIndex: Integer; AShift: TShiftState)
    var
      mIndex: Integer;
      mShift: TShiftState;
    begin
      mIndex := AIndex;
      mShift := AShift;
      mOwner.RunGuarded(
        procedure
        begin
          mOwner.DoubleClick(mIndex, mShift);
        end);
    end;
end;

procedure TAtlasIdeHandleTool.BeginStep;
var
  mEditor: IOTAFormEditor;
  mRoot: TComponent;
begin
  FreeAndNil(FStep);
  FChanged := False;
  if TAtlasDesignerAccess.Current(mEditor, mRoot) then
  begin
    FStep := TAtlasDesignerSnapshot.Create;
    FStep.Take(mEditor.FileName, mRoot);
  end;
end;

function TAtlasIdeHandleTool.InStep: Boolean;
begin
  Result := FStep <> nil;
end;

procedure TAtlasIdeHandleTool.CommitStep(const ADone: string; ARestore: Boolean);
var
  mEditor: IOTAFormEditor;
  mRoot: TComponent;
begin
  if FStep = nil then
  begin
    Exit;
  end;
  if ARestore then
  begin
    FStep.Restore;
  end
  else if FChanged then
  begin
    FUndo.Free;
    FUndo := FStep;
    FStep := nil;
    if TAtlasDesignerAccess.Current(mEditor, mRoot) and (TAtlasDesignerAccess.DesignerOf(mEditor) <> nil) then
    begin
      TAtlasDesignerAccess.DesignerOf(mEditor).Modified;
    end;
    Say(ADone);
  end;
  FreeAndNil(FStep);
  FChanged := False;
end;

function TAtlasIdeHandleTool.Dragging: Boolean;
begin
  Result := (FOverlay <> nil) and FOverlay.Dragging;
end;

procedure TAtlasIdeHandleTool.Toggle;
begin
  FActive := not FActive;
  if FActive then
  begin
    Tick;
  end
  else
  begin
    Hide;
  end;
end;

procedure TAtlasIdeHandleTool.Hide;
begin
  if FOverlay <> nil then
  begin
    FOverlay.HideHandles;
  end;
end;

procedure TAtlasIdeHandleTool.ApplyTheme;
begin
  if FOverlay <> nil then
  begin
    FOverlay.ApplyColors(TAtlasIdeStyle.Colors);
  end;
end;

procedure TAtlasIdeHandleTool.Popup(const APoint: TPoint);
var
  mItem: TMenuItem;
  mCaptions: TArray<string>;
  mIndex: Integer;
begin
  mCaptions := [ShowCaption] + Commands + [UndoCaption];
  FMenu.Items.Clear;
  for mIndex := 0 to High(mCaptions) do
  begin
    mItem := TMenuItem.Create(FMenu);
    mItem.Caption := mCaptions[mIndex];
    mItem.Tag := mIndex;
    mItem.OnClick := MenuClick;
    if mIndex = 0 then
    begin
      mItem.Checked := FActive;
    end
    else if mIndex = High(mCaptions) then
    begin
      mItem.Enabled := FUndo.CanRestore;
    end
    else
    begin
      mItem.Enabled := CommandEnabled(mIndex - 1);
    end;
    FMenu.Items.Add(mItem);
  end;
  FMenu.Popup(APoint.X, APoint.Y);
end;

procedure TAtlasIdeHandleTool.MenuClick(Sender: TObject);
var
  mTag, mLast: Integer;
begin
  mTag := TMenuItem(Sender).Tag;
  mLast := FMenu.Items.Count - 1;
  RunGuarded(
    procedure
    begin
      if mTag = 0 then
      begin
        Toggle;
      end
      else if mTag = mLast then
      begin
        if FUndo.Restore then
        begin
          Say(UndoneText);
          Tick;
        end;
      end
      else
      begin
        Command(mTag - 1);
      end;
    end);
end;

end.
