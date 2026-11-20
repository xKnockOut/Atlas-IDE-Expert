unit Atlas.Tests.FirstUse.Vcl;

// Einmal-Belegungen der VCL und der Oberfläche des Plugins (Formulare, Leinwände, Einstellungsseiten, Thema,
// Modul-Registry); Teil von TFirstUse (Atlas.Tests.FirstUse), dessen Kopf die Regeln für Einträge nennt.

interface

type
  TFirstUseVcl = class
  public
    /// <summary>Einmal vor dem ersten Test, aus TFirstUse.WarmUp: legt an, was VCL und Oberfläche beim ersten
    /// Gebrauch bis zum Programmende anlegen.</summary>
    class procedure WarmUp; static;
  end;

implementation

uses
  Winapi.Windows,
  Winapi.Messages,
  System.SysUtils,
  System.Types,
  System.Classes,
  Atlas.UI.Foundation.Theme,
  Atlas.Core.Modules.Contract,
  Atlas.Core.Modules.Registry,
  Atlas.UI.Settings.Contract,
  Atlas.UI.Settings.Section,
  Atlas.UI.Settings.Page,
  Vcl.Graphics,
  Vcl.Forms,
  Vcl.Clipbrd,
  Vcl.AppEvnts,
  Vcl.ComCtrls,
  Atlas.UI.Foundation.Dialog,
  Atlas.UI.Settings.Keys,
  Atlas.UI.Settings.Overview;

/// <summary>Abonnenten des IDE-Themas (TAtlasUiTheme): Die Liste entsteht beim ersten Abonnenten und wird im
/// Klassendestruktor freigegeben; ihre Kapazität wächst beim ersten Eintrag.</summary>
procedure WarmUpThemeListeners;
var
  mOwner: TObject;
begin
  mOwner := TObject.Create;
  try
    TAtlasUiTheme.Subscribe(mOwner,
      procedure
      begin
      end);
    TAtlasUiTheme.Unsubscribe(mOwner);
  finally
    mOwner.Free;
  end;
end;

/// <summary>Einstellungsseite (TAtlasSettingsPage) mit einem Abschnitt, einmal ohne und einmal mit Fenster: Die erste
/// Anmeldung legt die Listen der Modul-Registry an (frei mit der Registry in der Finalisierung von Base), das erste
/// Erzeugen der Steuerelemente legt einmalige Daten der VCL an (Themes, Schriften, Fensterklassen; frei in der
/// Finalisierung der VCL).</summary>
procedure WarmUpSettingsPage;
var
  mRegistration: IAtlasRegistration;
  mHost: TForm;
  mPage: TAtlasSettingsPage;
begin
  mRegistration := AtlasModuleRegistry.Provide(IAtlasSettingsSectionProvider,
    TAtlasSettingsSectionFactory.Create(TAtlasSettingsSection) as IAtlasSettingsSectionProvider);
  mRegistration.Revoke;
  TAtlasSettingsPage.Create(nil).Free;
  mHost := TForm.CreateNew(nil);
  try
    mPage := TAtlasSettingsPage.Create(mHost);
    mPage.Parent := mHost;
    mPage.HandleNeeded;
  finally
    mHost.Free;
  end;
end;

/// <summary>IDE-Thema auf ein Formular anwenden (TAtlasUiTheme): Farben und erstes Formular der VCL legen
/// einmalige Daten an, frei in der Finalisierung der VCL.</summary>
procedure WarmUpThemeApply;
var
  mForm: TForm;
begin
  // Erste Benutzung (VCL-Formular, Liste der Abonnenten) nicht dem ersten Test anrechnen.
  TAtlasUiTheme.Subscribed(nil);
  TAtlasUiTheme.Uninstall;
  TAtlasUiTheme.Colors;
  TAtlasUiTheme.Apply(nil);
  mForm := TForm.CreateNew(nil);
  try
    TAtlasUiTheme.Apply(mForm);
  finally
    mForm.Free;
  end;
end;

/// <summary>Erster Dialog mit Fenster (TAtlasDialog): einmalige Daten der VCL (Fensterklasse, Schrift), frei in deren
/// Finalisierung.</summary>
procedure WarmUpDialog;
var
  mDialog: TAtlasDialog;
begin
  // Erste Benutzung (VCL-Formular, Liste der Abonnenten des Themendienstes) nicht dem ersten Test anrechnen.
  mDialog := TAtlasDialog.CreateDialog(nil, 'Aufwärmen', 300);
  try
    mDialog.HandleNeeded;
  finally
    mDialog.Free;
  end;
end;

/// <summary>Seite der Tastenkürzel (TAtlasKeysPage): einmalige Daten ihrer Steuerelemente.</summary>
procedure WarmUpKeysPage;
begin
  TAtlasKeysPage.Create(nil).Free;
end;

/// <summary>Übersicht der Einstellungen einmal laden und durchsuchen: Katalog und Texte legen dabei einen
/// Zwischenspeicher bis Prozessende an.</summary>
procedure WarmUpSettingsOverview;
var
  mPage: TAtlasSettingsOverview;
begin
  mPage := TAtlasSettingsOverview.Create(nil);
  try
    mPage.Load(1, 1, 1);
    mPage.SearchFor('enabled');
  finally
    mPage.Free;
  end;
end;

/// <summary>Zwischenablage der VCL (Clipboard): Das Objekt entsteht beim ersten Zugriff und wird in der
/// Finalisierung von Vcl.Clipbrd freigegeben; das träfe sonst den ersten Test, der etwas kopiert (z. B. „Name
/// kopieren“ im Fenster „Komponenten suchen“).</summary>
procedure WarmUpDesignerClipboard;
begin
  if Clipboard = nil then
  begin
    raise EInvalidOperation.Create('Zwischenablage');
  end;
end;

/// <summary>Erstes Datenmodul des Prozesses (TDataModule, z. B. als Formular der Designer-Fälschung): Es meldet sich
/// bei Screen an (Vcl.Forms, TScreen.FDataModules wächst auf 4 Einträge und schrumpft nicht, frei mit Screen in der
/// Finalisierung der VCL); beim Freigeben nimmt es GlobalNameSpace zum Schreiben (Zähler je Thread, frei mit
/// GlobalNameSpace in der Finalisierung von System.Classes) und sperrt die Liste der offenen Verweise
/// (GlobalFixupList, Monitor-Datensatz, frei mit der Liste).</summary>
procedure WarmUpDataModule;
begin
  TDataModule.CreateNew(nil).Free;
end;

/// <summary>Erstes Ereignisobjekt der Anwendung (TApplicationEvents, z. B. im Scroller der Willkommenstafel): Es meldet
/// sich beim Verteiler der VCL an (Vcl.AppEvnts, MultiCaster); dessen Liste legt dabei Verwaltungsdaten und Kapazität an,
/// die beim Abmelden bleiben (208 Byte), frei mit dem Verteiler in der Finalisierung der VCL.</summary>
procedure WelcomeWarmUpApplicationEvents;
begin
  TApplicationEvents.Create(nil).Free;
end;

type
  /// <summary>Formular, das sich gleich nach dem Zeigen über WM_CLOSE selbst schließt: ShowModal kehrt damit über die
  /// modale Schleife zurück, ohne dass jemand klickt.</summary>
  TFirstModalForm = class(TForm)
  protected
    procedure DoShow; override;
  end;

procedure TFirstModalForm.DoShow;
begin
  inherited DoShow;
  PostMessage(Handle, WM_CLOSE, 0, 0);
end;

/// <summary>Erstes modales Fenster des Prozesses (TCustomForm.ShowModal): Screen merkt sich dabei die Fenster, deren
/// Fokus es zurückgibt (SaveFocusedList); die Liste entsteht beim ersten ShowModal und bleibt (56 Byte, z. B. im
/// Export-Dialog der Diagnose), frei mit Screen in der Finalisierung der VCL.</summary>
procedure DiagnosticsWarmUpFirstModal;
var
  mForm: TFirstModalForm;
begin
  mForm := TFirstModalForm.CreateNew(nil);
  try
    mForm.BorderStyle := bsNone;
    mForm.Position := poDesigned;
    mForm.SetBounds(-10000, -10000, 1, 1);
    mForm.ShowModal;
  finally
    mForm.Free;
  end;
end;

/// <summary>Liste aller Leinwände der VCL (Vcl.Graphics, TCanvas.Create trägt jede ein, TCanvas.Destroy trägt sie
/// aus): Ihre Kapazität wächst auf den Höchststand gleichzeitig lebender Leinwände und bleibt bis zur Finalisierung
/// von Vcl.Graphics. Jedes TCustomControl hat eine; eine Einstellungsseite mit allen Bereichen kommt auf mehrere
/// hundert (Block von 6.928 Byte für 864 Einträge). Viele Leinwände auf einmal anlegen und freigeben setzt den
/// Höchststand weit über den jedes Tests.</summary>
procedure WarmUpVclCanvasList;
const
  cCanvases = 4096;
var
  mCanvases: TArray<TCanvas>;
  mIndex: Integer;
begin
  SetLength(mCanvases, cCanvases);
  try
    for mIndex := 0 to High(mCanvases) do
    begin
      mCanvases[mIndex] := TCanvas.Create;
    end;
  finally
    for mIndex := 0 to High(mCanvases) do
    begin
      mCanvases[mIndex].Free;
    end;
  end;
end;

/// <summary>Liste der Zwischenablage-Formate der Bilder (Vcl.Graphics, GetClipboardFormats): Das erste TPicture
/// (etwa in TImage.Create, Karte von „Atlas entdecken“) legt sie an, mit Einträgen für jede Grafikklasse (208 Byte); sie
/// bleibt bis zur Finalisierung von Vcl.Graphics.</summary>
procedure WelcomeWarmUpPictureFormats;
begin
  TPicture.Create.Free;
end;

/// <summary>Liste der Bitmap-Leinwände mit Gerätekontext (Vcl.Graphics, TBitmapCanvas.CreateHandle trägt ein, das
/// Freigeben des Kontexts trägt aus): Ihre Kapazität wächst auf den Höchststand gleichzeitig offener Kontexte und
/// bleibt bis zur Finalisierung von Vcl.Graphics. Eine Bildliste legt beim Initialisieren mehrere an (80 Byte).
/// Viele Bitmaps mit Kontext auf einmal anlegen und freigeben setzt den Höchststand über den jedes Tests.</summary>
procedure WarmUpVclBitmapCanvases;
const
  cBitmaps = 64;
var
  mBitmaps: TArray<TBitmap>;
  mIndex: Integer;
begin
  SetLength(mBitmaps, cBitmaps);
  try
    for mIndex := 0 to High(mBitmaps) do
    begin
      mBitmaps[mIndex] := TBitmap.Create;
      mBitmaps[mIndex].SetSize(1, 1);
      mBitmaps[mIndex].Canvas.FillRect(TRect.Create(0, 0, 1, 1));
    end;
  finally
    for mIndex := 0 to High(mBitmaps) do
    begin
      mBitmaps[mIndex].Free;
    end;
  end;
end;

/// <summary>Musterbitmaps der VCL (Vcl.Graphics, TPatternManager): Ein eingerasteter TSpeedButton (Down, etwa
/// „Nach Klasse“ im Fenster „Atlas-Struktur“) füllt seine Fläche mit dem Muster aus clBtnFace und clBtnHighlight.
/// AllocPatternBitmap legt es je Farbpaar einmal an, mit Bild beim ersten Handle (328 Byte), und gibt es erst in der
/// Finalisierung von Vcl.Graphics frei.</summary>
procedure WarmUpVclPatternBitmap;
begin
  if AllocPatternBitmap(clBtnFace, clBtnHighlight).Handle = 0 then
  begin
    raise EInvalidOperation.Create('Musterbitmap');
  end;
end;

/// <summary>Zwischenspeicher der Gerätekontexte von Steuerelementen (Vcl.Controls, TControlCanvas.CreateHandle):
/// Seine Liste fasst höchstens vier Leinwände, ihre Kapazität entsteht beim ersten Textmessen auf einem
/// Steuerelement mit Fenster (48 Byte) und bleibt bis zur Finalisierung von Vcl.Controls. Fünf Formulare messen
/// gleichzeitig: Die Liste ist danach voll angelegt.</summary>
procedure WarmUpVclControlCanvas;
const
  cForms = 5;
var
  mForms: TArray<TForm>;
  mIndex: Integer;
begin
  SetLength(mForms, cForms);
  try
    for mIndex := 0 to High(mForms) do
    begin
      mForms[mIndex] := TForm.CreateNew(nil);
      mForms[mIndex].HandleNeeded;
      mForms[mIndex].Canvas.TextWidth('Atlas');
    end;
  finally
    for mIndex := 0 to High(mForms) do
    begin
      mForms[mIndex].Free;
    end;
  end;
end;

/// <summary>Erster DPI-Wechsel eines Formulars mit Liste: Die VCL legt dabei für die neue Auflösung Daten an, die bis zu
/// ihrer Finalisierung bleiben (72 Byte; der Leckbericht zeigt keinen Stapel). Den Nachrichtenverteiler dieses Wegs
/// legt WarmUpRtlSingletons (Atlas.Tests.FirstUse) an. Einmal auf 150 % und zurück skalieren, wie es Tests der Listen tun.</summary>
procedure WarmUpVclDpiChange;
var
  mForm: TForm;
  mList: TListView;
  mPPI: Integer;
begin
  mForm := TForm.CreateNew(nil);
  try
    mList := TListView.Create(mForm);
    mList.ViewStyle := vsReport;
    mList.Parent := mForm;
    mList.Columns.Add.Width := mForm.ScaleValue(100);
    mForm.HandleNeeded;
    mPPI := mForm.CurrentPPI;
    mForm.ScaleForPPI(mPPI * 3 div 2);
    mForm.ScaleForPPI(mPPI);
  finally
    mForm.Free;
  end;
end;

/// <summary>Liste der Beiträge in der Modul-Registry (TAtlasModuleRegistry, frei mit der Registry in der
/// Finalisierung von Base): Ihre Kapazität wächst auf den Höchststand gleichzeitiger Beiträge. Tests, die mehrere
/// Einstellungsbereiche auf einmal anmelden, heben ihn (400 Byte bei acht). Viele Beiträge auf einmal anmelden
/// und zurückziehen setzt ihn über den jedes Tests.</summary>
procedure WarmUpRegistryProvisions;
const
  cProvisions = 64;
var
  mRegistrations: TArray<IAtlasRegistration>;
  mIndex: Integer;
begin
  SetLength(mRegistrations, cProvisions);
  try
    for mIndex := 0 to High(mRegistrations) do
    begin
      mRegistrations[mIndex] := AtlasModuleRegistry.Provide(IAtlasSettingsSectionProvider,
        TAtlasSettingsSectionFactory.Create(TAtlasSettingsSection) as IAtlasSettingsSectionProvider);
    end;
  finally
    for mIndex := 0 to High(mRegistrations) do
    begin
      if mRegistrations[mIndex] <> nil then
      begin
        mRegistrations[mIndex].Revoke;
      end;
    end;
    mRegistrations := nil;
  end;
end;

{ TFirstUseVcl }

class procedure TFirstUseVcl.WarmUp;
begin
  WarmUpDataModule;
  WarmUpThemeListeners;
  WarmUpSettingsPage;
  WarmUpThemeApply;
  WarmUpDialog;
  WarmUpKeysPage;
  WarmUpSettingsOverview;
  WarmUpDesignerClipboard;
  WarmUpVclCanvasList;
  WarmUpVclBitmapCanvases;
  WarmUpVclPatternBitmap;
  WarmUpVclControlCanvas;
  WarmUpVclDpiChange;
  WarmUpRegistryProvisions;
  WelcomeWarmUpApplicationEvents;
  WelcomeWarmUpPictureFormats;
  DiagnosticsWarmUpFirstModal;
end;

end.
