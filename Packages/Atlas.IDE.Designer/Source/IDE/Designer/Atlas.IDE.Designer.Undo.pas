unit Atlas.IDE.Designer.Undo;

// Rückgängig im Formular-Designer (#1887, designer.undo, experimentell) in
// der IDE. Den Ablauf (Erfassen, Verlauf je Formular, Zurückladen) hält
// TAtlasDesignerUndoFlow über IAtlasDesignSurface; hier stehen nur die
// Anbindung an die Benachrichtigungen des Designers, das Einreihen in den
// Hauptthread, Tasten, Menü und Knopf.
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
  Vcl.Menus,
  DesignIntf,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Designer.Undo,
  Atlas.Core.Designer.UndoApply,
  Atlas.Core.Designer.UndoFlow,
  Atlas.Core.Designer.Surface,
  Atlas.UI.Designer.Bar,
  Atlas.IDE.Foundation.KeyHook,
  Atlas.IDE.Designer.Tool;

type
  TAtlasIdeDesignerUndo = class(TAtlasIdeDesignerTool)
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
    FNotification: TNotification;
    FNotificationRef: IDesignNotification;
    FKeys: TKeys;
    FMenu: TPopupMenu;
    FFlow: TAtlasDesignerUndoFlow;
    /// <summary>Einstellungen in den Ablauf übernehmen.</summary>
    procedure Sync;
    /// <summary>Erfassen nach dem laufenden Ereignis.</summary>
    procedure Queue;
    /// <summary>Verlauf des Formulars im aktiven Designer; False ohne Designer oder ohne Verlauf.</summary>
    function Active(out ASurface: IAtlasDesignSurface; out AHistory: TAtlasFormUndoHistory): Boolean;
    procedure Restore(AIndex: Integer);
    procedure AddItem(const ACaption: string; ATag: Integer; AChecked: Boolean);
    procedure BuildMenu;
    procedure MenuPopup(Sender: TObject);
    procedure MenuClick(Sender: TObject);
  protected
    /// <summary>Zeile in der Meldungsansicht, zusätzlich im Protokoll.</summary>
    procedure Say(const AText: string); override;
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
    /// <summary>Gründe beim Zurückladen in der Sprache der Oberfläche.</summary>
    class function Reasons: TAtlasUndoReasons; static;
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
  Atlas.IDE.Designer.Surface;

const
  cKeyPriority = 46;
  cMaxMenuSteps = 30;

{ TAtlasIdeDesignerUndo.TNotification }

procedure TAtlasIdeDesignerUndo.TNotification.ItemDeleted(const ADesigner: IDesigner; AItem: TPersistent);
begin
  if FOwner <> nil then
  begin
    FOwner.FFlow.ItemsChanged(TAtlasIdeDesignSurface.Wrap(ADesigner));
  end;
end;

procedure TAtlasIdeDesignerUndo.TNotification.ItemInserted(const ADesigner: IDesigner; AItem: TPersistent);
begin
  if FOwner <> nil then
  begin
    FOwner.FFlow.ItemsChanged(TAtlasIdeDesignSurface.Wrap(ADesigner));
  end;
end;

procedure TAtlasIdeDesignerUndo.TNotification.ItemsModified(const ADesigner: IDesigner);
begin
  if FOwner <> nil then
  begin
    FOwner.FFlow.ItemsChanged(TAtlasIdeDesignSurface.Wrap(ADesigner));
  end;
end;

procedure TAtlasIdeDesignerUndo.TNotification.SelectionChanged(const ADesigner: IDesigner;
  const ASelection: IDesignerSelections);
begin
  if FOwner <> nil then
  begin
    FOwner.FFlow.SelectionChanged(TAtlasIdeDesignSurface.Wrap(ADesigner));
  end;
end;

procedure TAtlasIdeDesignerUndo.TNotification.DesignerOpened(const ADesigner: IDesigner; AResurrecting: Boolean);
begin
  if FOwner <> nil then
  begin
    FOwner.FFlow.Opened(TAtlasIdeDesignSurface.Wrap(ADesigner));
  end;
end;

procedure TAtlasIdeDesignerUndo.TNotification.DesignerClosed(const ADesigner: IDesigner; AGoingDormant: Boolean);
begin
  if FOwner <> nil then
  begin
    FOwner.FFlow.Closed(TAtlasIdeDesignSurface.Wrap(ADesigner));
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
  inherited Create(AOnMessage);
  FFlow := TAtlasDesignerUndoFlow.Create(Words, Reasons);
  FFlow.OnQueue := Queue;
  Sync;
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
  FFlow.Free;
  inherited Destroy;
end;

procedure TAtlasIdeDesignerUndo.Say(const AText: string);
begin
  TAtlasGuard.Log('Designer undo: ' + AText);
  inherited Say(AText);
end;

procedure TAtlasIdeDesignerUndo.Sync;
begin
  FFlow.Enabled := Available(TAtlasIdeSettings.Current);
  FFlow.MaxSteps := TAtlasIdeSettings.Current.DesignerUndoSteps;
end;

procedure TAtlasIdeDesignerUndo.Queue;
var
  mOwner: TAtlasIdeDesignerUndo;
begin
  // Erst nach dem laufenden Ereignis: Dann stehen Lage, Größe und Werte fest.
  mOwner := Self;
  TAtlasMainThread.ForceQueue(TAtlasFeature.DesignerBar,
    procedure
    begin
      if FCurrent = mOwner then
      begin
        TAtlasGuard.Run(TAtlasFeature.DesignerBar,
          procedure
          begin
            mOwner.Sync;
            mOwner.FFlow.Capture;
          end);
      end;
    end);
end;

function TAtlasIdeDesignerUndo.Active(out ASurface: IAtlasDesignSurface;
  out AHistory: TAtlasFormUndoHistory): Boolean;
begin
  ASurface := TAtlasIdeDesignSurface.Active;
  Result := FFlow.Active(ASurface, AHistory);
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
  mSurface: IAtlasDesignSurface;
  mHistory: TAtlasFormUndoHistory;
  mIndex: Integer;
  mCaption: string;
begin
  FMenu.Items.Clear;
  if not Active(mSurface, mHistory) or (mHistory.Count < 2) then
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
    begin
      if mTag >= 0 then
      begin
        mOwner.Restore(mTag);
      end
      else if mTag = cMenuClear then
      begin
        // Aktueller Stand wird neuer Ausgangsstand.
        mOwner.FFlow.Reset(TAtlasIdeDesignSurface.Active);
      end;
    end);
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

class function TAtlasIdeDesignerUndo.Reasons: TAtlasUndoReasons;
begin
  Result.Delete := TAtlasDesignerStrings.Text(TAtlasDesignerTextId.UndoReasonDelete);
  Result.Missing := TAtlasDesignerStrings.Text(TAtlasDesignerTextId.UndoReasonMissing);
  Result.ClassUnknown := TAtlasDesignerStrings.Text(TAtlasDesignerTextId.UndoReasonClass);
  Result.Value := TAtlasDesignerStrings.Text(TAtlasDesignerTextId.UndoReasonValue);
  Result.Skipped := TAtlasDesignerStrings.Text(TAtlasDesignerTextId.UndoReasonInherited);
end;

/// <summary>Meldungen nach dem Zurückladen: fehlende Handler, nicht Hergestelltes.</summary>
function Messages(const AOutcome: TAtlasUndoOutcome): TArray<string>;
var
  mMissing: TAtlasUndoMissingMethod;
begin
  Result := nil;
  for mMissing in AOutcome.MissingMethods do
  begin
    Result := Result + [TAtlasDesignerStrings.Fmt(TAtlasDesignerTextId.UndoMethodMissing, [mMissing.Handler,
      mMissing.Component, mMissing.Path])];
  end;
  if Length(AOutcome.Failures) > 0 then
  begin
    Result := Result + [TAtlasDesignerStrings.Fmt(TAtlasDesignerTextId.UndoNotRestored,
      [string.Join('; ', AOutcome.Failures)])];
  end;
end;

procedure TAtlasIdeDesignerUndo.Restore(AIndex: Integer);
var
  mOutcome: TAtlasUndoOutcome;
  mMessage: string;
begin
  Sync;
  if not FFlow.Restore(TAtlasIdeDesignSurface.Active, AIndex, mOutcome) then
  begin
    Exit;
  end;
  for mMessage in Messages(mOutcome) do
  begin
    Say(mMessage);
  end;
end;

function TAtlasIdeDesignerUndo.Button: TAtlasDesignerButton;
var
  mSurface: IAtlasDesignSurface;
  mHistory: TAtlasFormUndoHistory;
  mHint: string;
begin
  mHint := TAtlasDesignerStrings.Text(TAtlasDesignerTextId.UndoHint);
  if Active(mSurface, mHistory) and mHistory.CanUndo then
  begin
    mHint := TAtlasDesignerStrings.Fmt(TAtlasDesignerTextId.UndoMenuUndo, [mHistory.State(mHistory.Index).Caption]) +
      sLineBreak + mHint;
  end;
  Result := TAtlasDesignerButton.Create(cId, TAtlasToolbarIcon.DesignerUndo, mHint);
  Result.Menu := True;
  Result.Enabled := mHistory <> nil;
end;

function TAtlasIdeDesignerUndo.CanUndo: Boolean;
begin
  Result := FFlow.CanUndo(TAtlasIdeDesignSurface.Active);
end;

function TAtlasIdeDesignerUndo.CanRedo: Boolean;
begin
  Result := FFlow.CanRedo(TAtlasIdeDesignSurface.Active);
end;

procedure TAtlasIdeDesignerUndo.Undo;
var
  mSurface: IAtlasDesignSurface;
  mHistory: TAtlasFormUndoHistory;
begin
  if Active(mSurface, mHistory) and mHistory.CanUndo then
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
  mSurface: IAtlasDesignSurface;
  mHistory: TAtlasFormUndoHistory;
begin
  if Active(mSurface, mHistory) and mHistory.CanRedo then
  begin
    Restore(mHistory.Index + 1);
  end;
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
  Sync;
end;

procedure TAtlasIdeDesignerUndo.Hide;
begin
  TAtlasKeyHook.Remove(FKeys);
end;

end.
