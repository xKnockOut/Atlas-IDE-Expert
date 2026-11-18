unit Atlas.IDE.Assistants.Banner;

// Anzeige „KI-Assistent aktiv“ im Atlas-Statusfeld (#1906, assistants.banner):
// Zusatzfeld mit dem, was TAtlasAssistantsActivity.View gerade sagt (Build
// läuft, Datei geändert, Pause). Ein Klick schaltet die Pause für
// KI-Assistenten um; die Eingänge lehnen dann neue Aufträge mit Grund ab.
// Das Feld wird alle cTickMs nachgeführt (eine angewendete Änderung
// verschwindet nach einer Minute) und nur neu gesetzt, wenn sich etwas
// geändert hat. Destroy entfernt das Feld, damit Base keinen Klick des Moduls
// mehr hält (Regel 3).

interface

uses
  System.Types,
  System.SysUtils,
  Vcl.ExtCtrls,
  Atlas.Core.Assistants.Activity;

type
  TAtlasIdeAssistantsBanner = class
  public const
    cFieldId = 'atlas.assistants';
    cTickMs = 1000;
  private
    FActivity: TAtlasAssistantsActivity;
    FTimer: TTimer;
    FShown: string;
    FOnToggle: TProc;
    procedure Tick(Sender: TObject);
    procedure Clicked(APoint: TPoint);
  public
    /// <summary>AActivity gehört der Composition und lebt länger als die Anzeige; AOnToggle schaltet die Pause um
    /// (Klick auf das Feld).</summary>
    constructor Create(AActivity: TAtlasAssistantsActivity; const AOnToggle: TProc);
    destructor Destroy; override;
    /// <summary>Feld sofort nachführen (nach einem Auftrag).</summary>
    procedure Refresh;
    /// <summary>Text des Felds für AView; '' = kein Feld.</summary>
    class function TextOf(const AView: TAtlasAssistantsActivityView): string; static;
  end;

implementation

uses
  Winapi.Windows,
  Atlas.Core.Status.Contract,
  Atlas.Core.Diagnostics.Guard,
  Atlas.IDE.Foundation.Host,
  Atlas.UI.Assistants.Strings;

/// <summary>„ · Name“ des KI-Assistenten, '' wenn unbekannt.</summary>
function ClientPart(const AClient: string): string;
begin
  Result := '';
  if AClient <> '' then
  begin
    Result := ' · ' + AClient;
  end;
end;

{ TAtlasIdeAssistantsBanner }

constructor TAtlasIdeAssistantsBanner.Create(AActivity: TAtlasAssistantsActivity; const AOnToggle: TProc);
begin
  inherited Create;
  FActivity := AActivity;
  FOnToggle := AOnToggle;
  FTimer := TTimer.Create(nil);
  FTimer.Interval := cTickMs;
  FTimer.OnTimer := Tick;
  FTimer.Enabled := True;
  Refresh;
end;

destructor TAtlasIdeAssistantsBanner.Destroy;
begin
  FTimer.Free;
  TAtlasIdeHost.SetStatusField(cFieldId, '', '', nil);
  inherited Destroy;
end;

class function TAtlasIdeAssistantsBanner.TextOf(const AView: TAtlasAssistantsActivityView): string;
begin
  case AView.Kind of
    TAtlasAssistantsActivityKind.Paused:
      Result := TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.BannerPaused);
    TAtlasAssistantsActivityKind.Building:
      Result := TAtlasAssistantsStrings.Fmt(TAtlasAssistantsTextId.BannerBuilding,
        [ClientPart(AView.Client), AView.Subject]);
    TAtlasAssistantsActivityKind.Edited:
      Result := TAtlasAssistantsStrings.Fmt(TAtlasAssistantsTextId.BannerEdited,
        [ClientPart(AView.Client), AView.Subject]);
  else
    Result := '';
  end;
end;

procedure TAtlasIdeAssistantsBanner.Refresh;
var
  mView: TAtlasAssistantsActivityView;
  mExtra: TAtlasStatusExtra;
begin
  mView := FActivity.View(GetTickCount64);
  mExtra := Default(TAtlasStatusExtra);
  mExtra.Id := cFieldId;
  mExtra.Text := TextOf(mView);
  if mExtra.Text = FShown then
  begin
    Exit;
  end;
  FShown := mExtra.Text;
  if mView.Kind = TAtlasAssistantsActivityKind.Paused then
  begin
    mExtra.Hint := TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.BannerHintPaused);
    mExtra.State := TAtlasStatusState.Yellow;
  end
  else
  begin
    mExtra.Hint := TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.BannerHintActive);
    mExtra.State := TAtlasStatusState.Green;
  end;
  if mExtra.Text <> '' then
  begin
    mExtra.OnClick := Clicked;
  end;
  TAtlasIdeHost.SetStatusItem(mExtra);
end;

procedure TAtlasIdeAssistantsBanner.Tick(Sender: TObject);
begin
  try
    Refresh;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Build, E);
  end;
end;

procedure TAtlasIdeAssistantsBanner.Clicked(APoint: TPoint);
begin
  FOnToggle();
  Refresh;
end;

end.
