unit Atlas.UI.Tests.SeriesMenu;

// Serien von Testläufen (#1782), reine VCL:
// - Frage nach der Anzahl für „N-mal ausführen …“ (Vorgabe tests.repeat.count).
// - Kontextmenü des Baums im Fenster „Atlas-Tests“: „Ausgewählte N-mal
//   ausführen …“, „Ausgewählte in zufälliger Reihenfolge ausführen“, „Mit
//   dieser Reihenfolge erneut ausführen“ und „Testserie abbrechen“. Gesperrt
//   ist, was gerade nicht geht: Während einer Serie bleibt nur Abbrechen.
// - Hat der Baum schon ein Kontextmenü (Testlisten, #2167, setzen und
//   nehmen es je nach Einstellung), hängen die Einträge unter einem Strich
//   daran; sonst ist dieses Menü das Kontextmenü. Das entscheidet sich bei
//   jedem Rechtsklick (OnContextPopup des Baums).

interface

uses
  System.SysUtils,
  System.Types,
  System.Classes,
  Vcl.Menus,
  Vcl.ComCtrls;

type
  /// <summary>Ereignisse des Kontextmenüs; nil = keins bzw. „nein“.</summary>
  TAtlasTestsSeriesHandlers = record
    OnRepeat: TProc;
    OnShuffle: TProc;
    OnShuffleAgain: TProc;
    OnCancel: TProc;
    /// <summary>Läuft eine Serie?</summary>
    Running: TFunc<Boolean>;
    /// <summary>Gibt es eine Reihenfolge zum Wiederholen?</summary>
    CanShuffleAgain: TFunc<Boolean>;
  end;

  TAtlasTestsSeriesMenu = class(TPopupMenu)
  private
    FHandlers: TAtlasTestsSeriesHandlers;
    FRepeat: TMenuItem;
    FShuffle: TMenuItem;
    FAgain: TMenuItem;
    FCancel: TMenuItem;
    /// <summary>Strich vor den Einträgen, wenn sie an einem fremden Menü hängen.</summary>
    FLine: TMenuItem;
    function NewItem(const ACaption: string): TMenuItem;
    procedure ItemClick(Sender: TObject);
    procedure TreeContextPopup(Sender: TObject; MousePos: TPoint; var Handled: Boolean);
  public
    /// <summary>Einträge an das Kontextmenü von ATree mit AHandlers; das Menü gehört ATree und lebt höchstens so
    /// lange wie er. Belegt OnContextPopup von ATree.</summary>
    class procedure Attach(ATree: TTreeView; const AHandlers: TAtlasTestsSeriesHandlers); static;
    /// <summary>Einträge von ATree entfernen (Ereignisse zeigen danach nirgends mehr hin); nichts ohne.</summary>
    class procedure Detach(ATree: TTreeView); static;
    /// <summary>Anzahl für „N-mal ausführen …“ erfragen, vorbelegt mit ADefault; AMin und AMax nennt die Frage.
    /// False, wenn der Benutzer abbricht; AText ist die Eingabe (prüft der Aufrufer).</summary>
    class function AskCount(ADefault, AMin, AMax: Integer; out AText: string): Boolean; static;
  end;

implementation

uses
  Vcl.Dialogs,
  Atlas.UI.Tests.Strings;

const
  cLineCaption = '-';

function Answer(const AFunc: TFunc<Boolean>): Boolean;
begin
  Result := Assigned(AFunc) and AFunc();
end;

procedure Fire(const AProc: TProc);
begin
  if Assigned(AProc) then
  begin
    AProc();
  end;
end;

{ TAtlasTestsSeriesMenu }

class procedure TAtlasTestsSeriesMenu.Attach(ATree: TTreeView; const AHandlers: TAtlasTestsSeriesHandlers);
var
  mMenu: TAtlasTestsSeriesMenu;
begin
  mMenu := TAtlasTestsSeriesMenu.Create(ATree);
  mMenu.FHandlers := AHandlers;
  mMenu.FLine := mMenu.NewItem(cLineCaption);
  mMenu.FRepeat := mMenu.NewItem(TAtlasTestsStrings.Text(TAtlasTestsTextId.SeriesMenuRepeat));
  mMenu.FShuffle := mMenu.NewItem(TAtlasTestsStrings.Text(TAtlasTestsTextId.SeriesMenuShuffle));
  mMenu.FAgain := mMenu.NewItem(TAtlasTestsStrings.Text(TAtlasTestsTextId.SeriesShuffleAgainCommand));
  mMenu.FCancel := mMenu.NewItem(TAtlasTestsStrings.Text(TAtlasTestsTextId.SeriesCancelCommand));
  ATree.OnContextPopup := mMenu.TreeContextPopup;
end;

class procedure TAtlasTestsSeriesMenu.Detach(ATree: TTreeView);
var
  mIndex: Integer;
begin
  ATree.OnContextPopup := nil;
  for mIndex := ATree.ComponentCount - 1 downto 0 do
  begin
    if ATree.Components[mIndex] is TAtlasTestsSeriesMenu then
    begin
      // Freigeben meldet sich beim Baum ab (PopupMenu wird nil); die Einträge lösen sich aus einem fremden Menü.
      ATree.Components[mIndex].Free;
    end;
  end;
end;

function TAtlasTestsSeriesMenu.NewItem(const ACaption: string): TMenuItem;
begin
  Result := TMenuItem.Create(Self);
  Result.Caption := ACaption;
  Result.OnClick := ItemClick;
  Items.Add(Result);
end;

procedure TAtlasTestsSeriesMenu.TreeContextPopup(Sender: TObject; MousePos: TPoint; var Handled: Boolean);
var
  mTree: TTreeView;
  mTarget: TMenuItem;
  mItem: TMenuItem;
  mRunning: Boolean;
begin
  mTree := Sender as TTreeView;
  if mTree.PopupMenu = nil then
  begin
    mTree.PopupMenu := Self;
  end;
  mTarget := mTree.PopupMenu.Items;
  for mItem in TArray<TMenuItem>.Create(FLine, FRepeat, FShuffle, FAgain, FCancel) do
  begin
    if mItem.Parent <> mTarget then
    begin
      if mItem.Parent <> nil then
      begin
        mItem.Parent.Remove(mItem);
      end;
      mTarget.Add(mItem);
    end;
  end;
  FLine.Visible := mTree.PopupMenu <> Self;
  mRunning := Answer(FHandlers.Running);
  FRepeat.Enabled := not mRunning;
  FShuffle.Enabled := not mRunning;
  FAgain.Enabled := not mRunning and Answer(FHandlers.CanShuffleAgain);
  FCancel.Enabled := mRunning;
end;

procedure TAtlasTestsSeriesMenu.ItemClick(Sender: TObject);
begin
  if Sender = FRepeat then
  begin
    Fire(FHandlers.OnRepeat);
  end
  else if Sender = FShuffle then
  begin
    Fire(FHandlers.OnShuffle);
  end
  else if Sender = FAgain then
  begin
    Fire(FHandlers.OnShuffleAgain);
  end
  else if Sender = FCancel then
  begin
    Fire(FHandlers.OnCancel);
  end;
end;

class function TAtlasTestsSeriesMenu.AskCount(ADefault, AMin, AMax: Integer; out AText: string): Boolean;
begin
  AText := IntToStr(ADefault);
  Result := InputQuery(TAtlasTestsStrings.Text(TAtlasTestsTextId.SeriesAskTitle),
    TAtlasTestsStrings.Fmt(TAtlasTestsTextId.SeriesAskPrompt, [AMin, AMax]), AText);
end;

end.
