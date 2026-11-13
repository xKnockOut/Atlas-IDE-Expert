unit Atlas.UI.Tests.SeriesMenu;

// Serien von Testläufen (#1782), reine VCL:
// - Frage nach der Anzahl für „N-mal ausführen …“ (Vorgabe tests.repeat.count).
// - Kontextmenü des Baums im Fenster „Atlas-Tests“: „Ausgewählte N-mal
//   ausführen …“, „Ausgewählte in zufälliger Reihenfolge ausführen“, „Mit
//   dieser Reihenfolge erneut ausführen“ und „Testserie abbrechen“. Gesperrt
//   ist, was gerade nicht geht: Während einer Serie bleibt nur Abbrechen.

interface

uses
  System.SysUtils,
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
    function NewItem(const ACaption: string): TMenuItem;
    procedure ItemClick(Sender: TObject);
    procedure MenuShowing(Sender: TObject);
  public
    /// <summary>Kontextmenü an ATree mit AHandlers; es gehört ATree und lebt höchstens so lange wie er.</summary>
    class procedure Attach(ATree: TTreeView; const AHandlers: TAtlasTestsSeriesHandlers); static;
    /// <summary>Kontextmenü von ATree entfernen (Ereignisse zeigen danach nirgends mehr hin); nichts ohne.</summary>
    class procedure Detach(ATree: TTreeView); static;
    /// <summary>Anzahl für „N-mal ausführen …“ erfragen, vorbelegt mit ADefault; AMin und AMax nennt die Frage.
    /// False, wenn der Benutzer abbricht; AText ist die Eingabe (prüft der Aufrufer).</summary>
    class function AskCount(ADefault, AMin, AMax: Integer; out AText: string): Boolean; static;
  end;

implementation

uses
  Vcl.Dialogs,
  Atlas.UI.Tests.Strings;

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
  mMenu.FRepeat := mMenu.NewItem(TAtlasTestsStrings.Text(TAtlasTestsTextId.SeriesMenuRepeat));
  mMenu.FShuffle := mMenu.NewItem(TAtlasTestsStrings.Text(TAtlasTestsTextId.SeriesMenuShuffle));
  mMenu.FAgain := mMenu.NewItem(TAtlasTestsStrings.Text(TAtlasTestsTextId.SeriesShuffleAgainCommand));
  mMenu.FCancel := mMenu.NewItem(TAtlasTestsStrings.Text(TAtlasTestsTextId.SeriesCancelCommand));
  mMenu.OnPopup := mMenu.MenuShowing;
  ATree.PopupMenu := mMenu;
end;

class procedure TAtlasTestsSeriesMenu.Detach(ATree: TTreeView);
begin
  if ATree.PopupMenu is TAtlasTestsSeriesMenu then
  begin
    // Freigeben meldet sich beim Baum ab (PopupMenu wird nil).
    ATree.PopupMenu.Free;
  end;
end;

function TAtlasTestsSeriesMenu.NewItem(const ACaption: string): TMenuItem;
begin
  Result := TMenuItem.Create(Self);
  Result.Caption := ACaption;
  Result.OnClick := ItemClick;
  Items.Add(Result);
end;

procedure TAtlasTestsSeriesMenu.MenuShowing(Sender: TObject);
var
  mRunning: Boolean;
begin
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
