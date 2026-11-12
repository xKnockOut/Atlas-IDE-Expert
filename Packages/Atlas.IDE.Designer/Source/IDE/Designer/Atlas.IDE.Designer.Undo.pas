unit Atlas.IDE.Designer.Undo;

// Rückgängig im Formular-Designer (#1887, designer.undo, experimentell) in
// der IDE. Verlauf, Vergleich und Änderungstexte rechnen
// TAtlasFormUndoHistory und TAtlasFormUndo, das Zurückladen
// TAtlasDesignerUndoApply.
// - Erfassen: IDesignNotification (eingefügt, gelöscht, geändert) reiht nach
//   dem laufenden Ereignis ein Erfassen ein; dann schreibt Atlas den
//   Formulartext wie beim Speichern und hängt ihn mit lesbarem Text an den
//   Verlauf dieses Formulars (höchstens designer.undoSteps Schritte, nur im
//   Speicher). Den Ausgangsstand nimmt Atlas beim Öffnen des Designers bzw.
//   bei der ersten Auswahl. Speichern leert den Verlauf nicht, Schließen
//   des Formulars schon.
// - Strg+Z und Strg+Umschalt+Z, solange der Designer den Fokus hat und es
//   einen Schritt gibt; sonst bleibt die Taste bei der IDE (ihr „Löschen
//   rückgängig“).
// - Knopf der Designer-Leiste: Symbol nimmt den letzten Schritt zurück, der
//   Pfeil öffnet die Liste aller Schritte („Panel1.Align: alNone →
//   alClient“); ein Klick springt auf diesen Stand.
// Nur im Hauptthread.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  System.Generics.Collections,
  Vcl.Menus,
  DesignIntf,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Designer.Undo,
  Atlas.UI.Designer.Bar,
  Atlas.IDE.Foundation.KeyHook;

type
  TAtlasIdeDesignerUndo = class
  public const
    cId = 'designerUndo';
  private type
    TNotification = class(TInterfacedObject, IDesignNotification)
    private
      FOwner: TAtlasIdeDesignerUndo;
    public
      procedure ItemDeleted(const ADesigner: IDesigner; AItem: TPersistent);
      procedure ItemInserted(const ADesigner: IDesigner; AItem: TPersistent);
      procedure ItemsModified(const ADesigner: IDesigner);
      procedure SelectionChanged(const ADesigner: IDesigner; const ASelection: IDesignerSelections);
      procedure DesignerOpened(const ADesigner: IDesigner; AResurrecting: Boolean);
      procedure DesignerClosed(const ADesigner: IDesigner; AGoingDormant: Boolean);
    end;

    TKeys = class(TAtlasKeyClient)
    private
      FOwner: TAtlasIdeDesignerUndo;
    protected
      function WantsKey(AKey: Word; AShift: TShiftState): Boolean; override;
      procedure HandleKey(AKey: Word; AShift: TShiftState); override;
    end;
  private class var
    FCurrent: TAtlasIdeDesignerUndo;
  private
    FOnMessage: TProc<string>;
    FNotification: TNotification;
    FNotificationRef: IDesignNotification;
    FKeys: TKeys;
    FMenu: TPopupMenu;
    /// <summary>Verlauf je Formular (Wurzelkomponente im Designer).</summary>
    FHistories: TObjectDictionary<TComponent, TAtlasFormUndoHistory>;
    /// <summary>Designer, dessen Stand nach dem laufenden Ereignis zu erfassen ist.</summary>
    FPending: IDesigner;
    FQueued: Boolean;
    /// <summary>Atlas lädt gerade zurück: eigene Änderungen nicht erfassen.</summary>
    FBusy: Boolean;
    procedure Say(const AText: string);
    procedure Queue(const ADesigner: IDesigner);
    procedure Capture;
    procedure Closed(const ADesigner: IDesigner);
    function HistoryOf(ARoot: TComponent): TAtlasFormUndoHistory;
    /// <summary>Verlauf des Formulars im aktiven Designer; False ohne Designer oder ohne Verlauf.</summary>
    function Active(out ADesigner: IDesigner; out AHistory: TAtlasFormUndoHistory): Boolean;
    procedure Restore(AIndex: Integer);
    procedure AddItem(const ACaption: string; ATag: Integer; AChecked: Boolean);
    procedure BuildMenu;
    procedure MenuPopup(Sender: TObject);
    procedure MenuClick(Sender: TObject);
  public const
    /// <summary>Kennung im Menü: Liste leeren (Schritte haben ihren Index als Tag).</summary>
    cMenuClear = -1;
  public
    /// <summary>AOnMessage: Zeile in der Meldungsansicht.</summary>
    constructor Create(const AOnMessage: TProc<string>);
    destructor Destroy; override;
    class function Available(const ASettings: TAtlasPluginSettings): Boolean; static;
    /// <summary>Formate der Änderungstexte in der Sprache der Oberfläche.</summary>
    class function Words: TAtlasUndoWords; static;
    function Button: TAtlasDesignerButton;
    function CanUndo: Boolean;
    function CanRedo: Boolean;
    procedure Undo;
    procedure Redo;
    /// <summary>Liste der Schritte an APoint (Bildschirm).</summary>
    procedure Popup(const APoint: TPoint);
    /// <summary>Takt der Leiste: Tasten nach den Einstellungen an- und abmelden.</summary>
    procedure Tick;
    procedure Hide;
  end;

implementation

uses
  ToolsAPI,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.EditorToolbar.Icons,
  Atlas.UI.Designer.Strings,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Designer.Access,
  Atlas.IDE.Designer.UndoApply;

const
  cKeyPriority = 46;
  cMaxMenuSteps = 30;

{ TAtlasIdeDesignerUndo.TNotification }

procedure TAtlasIdeDesignerUndo.TNotification.ItemDeleted(const ADesigner: IDesigner; AItem: TPersistent);
begin
  if FOwner <> nil then
  begin
    FOwner.Queue(ADesigner);
  end;
end;

procedure TAtlasIdeDesignerUndo.TNotification.ItemInserted(const ADesigner: IDesigner; AItem: TPersistent);
begin
  if FOwner <> nil then
  begin
    FOwner.Queue(ADesigner);
  end;
end;

procedure TAtlasIdeDesignerUndo.TNotification.ItemsModified(const ADesigner: IDesigner);
begin
  if FOwner <> nil then
  begin
    FOwner.Queue(ADesigner);
  end;
end;

procedure TAtlasIdeDesignerUndo.TNotification.SelectionChanged(const ADesigner: IDesigner;
  const ASelection: IDesignerSelections);
begin
  // Vor der ersten Änderung den Ausgangsstand kennen.
  if (FOwner <> nil) and (ADesigner <> nil) and (ADesigner.Root <> nil) and
    not FOwner.FHistories.ContainsKey(ADesigner.Root) then
  begin
    FOwner.Queue(ADesigner);
  end;
end;

procedure TAtlasIdeDesignerUndo.TNotification.DesignerOpened(const ADesigner: IDesigner; AResurrecting: Boolean);
begin
  if FOwner <> nil then
  begin
    FOwner.Queue(ADesigner);
  end;
end;

procedure TAtlasIdeDesignerUndo.TNotification.DesignerClosed(const ADesigner: IDesigner; AGoingDormant: Boolean);
begin
  if FOwner <> nil then
  begin
    FOwner.Closed(ADesigner);
  end;
end;

{ TAtlasIdeDesignerUndo.TKeys }

function TAtlasIdeDesignerUndo.TKeys.WantsKey(AKey: Word; AShift: TShiftState): Boolean;
begin
  Result := (AKey = Ord('Z')) and TAtlasDesignerAccess.Focused;
  if Result and (AShift = [ssCtrl]) then
  begin
    Result := FOwner.CanUndo;
  end
  else if Result and (AShift = [ssCtrl, ssShift]) then
  begin
    Result := FOwner.CanRedo;
  end
  else
  begin
    Result := False;
  end;
end;

procedure TAtlasIdeDesignerUndo.TKeys.HandleKey(AKey: Word; AShift: TShiftState);
var
  mOwner: TAtlasIdeDesignerUndo;
  mRedo: Boolean;
begin
  mOwner := FOwner;
  mRedo := ssShift in AShift;
  TAtlasGuard.Run(TAtlasFeature.DesignerBar,
    procedure
    begin
      if mRedo then
      begin
        mOwner.Redo;
      end
      else
      begin
        mOwner.Undo;
      end;
    end);
end;

{ TAtlasIdeDesignerUndo }

constructor TAtlasIdeDesignerUndo.Create(const AOnMessage: TProc<string>);
begin
  inherited Create;
  FOnMessage := AOnMessage;
  FHistories := TObjectDictionary<TComponent, TAtlasFormUndoHistory>.Create([doOwnsValues]);
  FKeys := TKeys.Create(cKeyPriority);
  FKeys.FOwner := Self;
  FMenu := TPopupMenu.Create(nil);
  FMenu.OnPopup := MenuPopup;
  FNotification := TNotification.Create;
  FNotification.FOwner := Self;
  FNotificationRef := FNotification;
  RegisterDesignNotification(FNotificationRef);
  FCurrent := Self;
end;

destructor TAtlasIdeDesignerUndo.Destroy;
begin
  if FCurrent = Self then
  begin
    FCurrent := nil;
  end;
  if FNotification <> nil then
  begin
    FNotification.FOwner := nil;
    UnregisterDesignNotification(FNotificationRef);
    FNotificationRef := nil;
  end;
  TAtlasKeyHook.Remove(FKeys);
  FKeys.Free;
  FMenu.Free;
  FPending := nil;
  FHistories.Free;
  inherited Destroy;
end;

class function TAtlasIdeDesignerUndo.Available(const ASettings: TAtlasPluginSettings): Boolean;
begin
  Result := ASettings.DesignerUndo;
end;

class function TAtlasIdeDesignerUndo.Words: TAtlasUndoWords;
begin
  Result.Moved := TAtlasDesignerStrings.Text(TAtlasDesignerTextId.UndoMoved);
  Result.Resized := TAtlasDesignerStrings.Text(TAtlasDesignerTextId.UndoResized);
  Result.Changed := TAtlasDesignerStrings.Text(TAtlasDesignerTextId.UndoChanged);
  Result.ChangedMany := TAtlasDesignerStrings.Text(TAtlasDesignerTextId.UndoChangedMany);
  Result.Inserted := TAtlasDesignerStrings.Text(TAtlasDesignerTextId.UndoInserted);
  Result.Deleted := TAtlasDesignerStrings.Text(TAtlasDesignerTextId.UndoDeleted);
  Result.Renamed := TAtlasDesignerStrings.Text(TAtlasDesignerTextId.UndoRenamed);
  Result.MovedMany := TAtlasDesignerStrings.Text(TAtlasDesignerTextId.UndoMovedMany);
  Result.Several := TAtlasDesignerStrings.Text(TAtlasDesignerTextId.UndoSeveral);
  Result.DefaultValue := TAtlasDesignerStrings.Text(TAtlasDesignerTextId.UndoDefault);
end;

procedure TAtlasIdeDesignerUndo.Say(const AText: string);
begin
  TAtlasGuard.Log('Designer undo: ' + AText);
  if Assigned(FOnMessage) then
  begin
    FOnMessage(AText);
  end;
end;

procedure TAtlasIdeDesignerUndo.Queue(const ADesigner: IDesigner);
var
  mOwner: TAtlasIdeDesignerUndo;
begin
  if FBusy or (ADesigner = nil) or not Available(TAtlasIdeSettings.Current) then
  begin
    Exit;
  end;
  FPending := ADesigner;
  if FQueued then
  begin
    Exit;
  end;
  // Erst nach dem laufenden Ereignis: Dann stehen Lage, Größe und Werte fest.
  FQueued := True;
  mOwner := Self;
  TAtlasMainThread.ForceQueue(TAtlasFeature.DesignerBar,
    procedure
    begin
      if FCurrent = mOwner then
      begin
        mOwner.FQueued := False;
        TAtlasGuard.Run(TAtlasFeature.DesignerBar,
          procedure
          begin
            mOwner.Capture;
          end);
      end;
    end);
end;

function TAtlasIdeDesignerUndo.HistoryOf(ARoot: TComponent): TAtlasFormUndoHistory;
begin
  if not FHistories.TryGetValue(ARoot, Result) then
  begin
    Result := TAtlasFormUndoHistory.Create(TAtlasIdeSettings.Current.DesignerUndoSteps);
    FHistories.Add(ARoot, Result);
  end;
end;

procedure TAtlasIdeDesignerUndo.Capture;
var
  mDesigner: IDesigner;
  mRoot: TComponent;
  mHistory: TAtlasFormUndoHistory;
  mText: string;
begin
  mDesigner := FPending;
  FPending := nil;
  if (mDesigner = nil) or FBusy then
  begin
    Exit;
  end;
  if not Available(TAtlasIdeSettings.Current) then
  begin
    FHistories.Clear;
    Exit;
  end;
  mRoot := mDesigner.Root;
  if mRoot = nil then
  begin
    Exit;
  end;
  mText := TAtlasDesignerAccess.FormText(mRoot, mDesigner);
  mHistory := HistoryOf(mRoot);
  mHistory.MaxSteps := TAtlasIdeSettings.Current.DesignerUndoSteps;
  if mHistory.Count = 0 then
  begin
    mHistory.Add(mText, '');
  end
  else
  begin
    mHistory.Add(mText, TAtlasFormUndo.Describe(mHistory.State(mHistory.Index).Text, mText, Words));
  end;
end;

procedure TAtlasIdeDesignerUndo.Closed(const ADesigner: IDesigner);
begin
  if (ADesigner = nil) or (ADesigner.Root = nil) then
  begin
    Exit;
  end;
  if (FPending <> nil) and (FPending.Root = ADesigner.Root) then
  begin
    FPending := nil;
  end;
  FHistories.Remove(ADesigner.Root);
end;

function TAtlasIdeDesignerUndo.Active(out ADesigner: IDesigner; out AHistory: TAtlasFormUndoHistory): Boolean;
var
  mEditor: IOTAFormEditor;
  mRoot: TComponent;
begin
  ADesigner := nil;
  AHistory := nil;
  Result := Available(TAtlasIdeSettings.Current) and TAtlasDesignerAccess.Current(mEditor, mRoot) and
    FHistories.TryGetValue(mRoot, AHistory);
  if Result then
  begin
    ADesigner := TAtlasDesignerAccess.DesignerOf(mEditor);
    Result := ADesigner <> nil;
  end;
end;

function TAtlasIdeDesignerUndo.CanUndo: Boolean;
var
  mDesigner: IDesigner;
  mHistory: TAtlasFormUndoHistory;
begin
  Result := Active(mDesigner, mHistory) and mHistory.CanUndo;
end;

function TAtlasIdeDesignerUndo.CanRedo: Boolean;
var
  mDesigner: IDesigner;
  mHistory: TAtlasFormUndoHistory;
begin
  Result := Active(mDesigner, mHistory) and mHistory.CanRedo;
end;

procedure TAtlasIdeDesignerUndo.Undo;
var
  mDesigner: IDesigner;
  mHistory: TAtlasFormUndoHistory;
begin
  if Active(mDesigner, mHistory) and mHistory.CanUndo then
  begin
    Restore(mHistory.Index - 1);
  end
  else
  begin
    Say(TAtlasDesignerStrings.Text(TAtlasDesignerTextId.UndoNothing));
  end;
end;

procedure TAtlasIdeDesignerUndo.Redo;
var
  mDesigner: IDesigner;
  mHistory: TAtlasFormUndoHistory;
begin
  if Active(mDesigner, mHistory) and mHistory.CanRedo then
  begin
    Restore(mHistory.Index + 1);
  end;
end;

/// <summary>Meldungen nach dem Zurückladen: fehlende Handler, nicht Hergestelltes.</summary>
function Messages(AApply: TAtlasDesignerUndoApply): TArray<string>;
var
  mMissing: TAtlasUndoMissingMethod;
begin
  Result := nil;
  for mMissing in AApply.MissingMethods do
  begin
    Result := Result + [TAtlasDesignerStrings.Fmt(TAtlasDesignerTextId.UndoMethodMissing, [mMissing.Handler,
      mMissing.Component, mMissing.Path])];
  end;
  if Length(AApply.Failures) > 0 then
  begin
    Result := Result + [TAtlasDesignerStrings.Fmt(TAtlasDesignerTextId.UndoNotRestored,
      [string.Join('; ', AApply.Failures)])];
  end;
end;

procedure TAtlasIdeDesignerUndo.Restore(AIndex: Integer);
var
  mEditor: IOTAFormEditor;
  mRoot: TComponent;
  mDesigner: IDesigner;
  mHistory: TAtlasFormUndoHistory;
  mTarget: string;
  mApply: TAtlasDesignerUndoApply;
  mMessage: string;
begin
  if not Active(mDesigner, mHistory) or (AIndex < 0) or (AIndex >= mHistory.Count) or
    not TAtlasDesignerAccess.Current(mEditor, mRoot) then
  begin
    Exit;
  end;
  mTarget := mHistory.State(AIndex).Text;
  mApply := TAtlasDesignerUndoApply.Create(mEditor, mDesigner, mRoot);
  FBusy := True;
  try
    try
      mApply.Run(TAtlasFormUndo.Plan(TAtlasDesignerAccess.FormText(mRoot, mDesigner), mTarget), mTarget);
    finally
      mDesigner.Modified;
      // Der tatsächliche Stand gilt; was nicht herstellbar war, bleibt so auch beim nächsten Schritt.
      mHistory.MoveTo(AIndex, TAtlasDesignerAccess.FormText(mRoot, mDesigner));
      FBusy := False;
    end;
    for mMessage in Messages(mApply) do
    begin
      Say(mMessage);
    end;
  finally
    mApply.Free;
  end;
end;

procedure TAtlasIdeDesignerUndo.AddItem(const ACaption: string; ATag: Integer; AChecked: Boolean);
var
  mItem: TMenuItem;
begin
  mItem := TMenuItem.Create(FMenu);
  mItem.Caption := ACaption;
  mItem.Tag := ATag;
  mItem.Checked := AChecked;
  mItem.OnClick := MenuClick;
  FMenu.Items.Add(mItem);
end;

procedure TAtlasIdeDesignerUndo.BuildMenu;
var
  mDesigner: IDesigner;
  mHistory: TAtlasFormUndoHistory;
  mIndex: Integer;
  mCaption: string;
begin
  FMenu.Items.Clear;
  if not Active(mDesigner, mHistory) or (mHistory.Count < 2) then
  begin
    AddItem(TAtlasDesignerStrings.Text(TAtlasDesignerTextId.UndoEmpty), cMenuClear - 1, False);
    FMenu.Items[0].Enabled := False;
    Exit;
  end;
  // Neueste oben; der Haken markiert den aktuellen Stand.
  mIndex := mHistory.Count - 1;
  while (mIndex >= 0) and (mIndex >= mHistory.Count - cMaxMenuSteps) do
  begin
    mCaption := mHistory.State(mIndex).Caption;
    if mIndex = 0 then
    begin
      mCaption := TAtlasDesignerStrings.Text(TAtlasDesignerTextId.UndoInitial);
    end;
    AddItem(StringReplace(mCaption, '&', '&&', [rfReplaceAll]), mIndex, mIndex = mHistory.Index);
    Dec(mIndex);
  end;
  FMenu.Items.Add(NewLine);
  AddItem(TAtlasDesignerStrings.Text(TAtlasDesignerTextId.UndoClear), cMenuClear, False);
end;

procedure TAtlasIdeDesignerUndo.MenuPopup(Sender: TObject);
begin
  BuildMenu;
end;

procedure TAtlasIdeDesignerUndo.MenuClick(Sender: TObject);
var
  mTag: Integer;
  mOwner: TAtlasIdeDesignerUndo;
begin
  mTag := Integer(TMenuItem(Sender).Tag);
  mOwner := Self;
  TAtlasGuard.Run(TAtlasFeature.DesignerBar,
    procedure
    var
      mDesigner: IDesigner;
      mHistory: TAtlasFormUndoHistory;
    begin
      if mTag >= 0 then
      begin
        mOwner.Restore(mTag);
      end
      else if (mTag = cMenuClear) and mOwner.Active(mDesigner, mHistory) then
      begin
        // Aktueller Stand wird neuer Ausgangsstand.
        mHistory.Clear;
        mHistory.Add(TAtlasDesignerAccess.FormText(mDesigner.Root, mDesigner), '');
      end;
    end);
end;

function TAtlasIdeDesignerUndo.Button: TAtlasDesignerButton;
var
  mDesigner: IDesigner;
  mHistory: TAtlasFormUndoHistory;
  mHint: string;
begin
  mHint := TAtlasDesignerStrings.Text(TAtlasDesignerTextId.UndoHint);
  if Active(mDesigner, mHistory) and mHistory.CanUndo then
  begin
    mHint := TAtlasDesignerStrings.Fmt(TAtlasDesignerTextId.UndoMenuUndo, [mHistory.State(mHistory.Index).Caption]) +
      sLineBreak + mHint;
  end;
  Result := TAtlasDesignerButton.Create(cId, TAtlasToolbarIcon.DesignerUndo, mHint);
  Result.Menu := True;
  Result.Enabled := Active(mDesigner, mHistory);
end;

procedure TAtlasIdeDesignerUndo.Popup(const APoint: TPoint);
begin
  // OnPopup baut das Menü.
  FMenu.Popup(APoint.X, APoint.Y);
end;

procedure TAtlasIdeDesignerUndo.Tick;
begin
  if Available(TAtlasIdeSettings.Current) and TAtlasDesignerAccess.Shown then
  begin
    TAtlasKeyHook.Add(FKeys);
  end
  else
  begin
    TAtlasKeyHook.Remove(FKeys);
  end;
  if not Available(TAtlasIdeSettings.Current) and (FHistories.Count > 0) then
  begin
    FHistories.Clear;
  end;
end;

procedure TAtlasIdeDesignerUndo.Hide;
begin
  TAtlasKeyHook.Remove(FKeys);
end;

end.
