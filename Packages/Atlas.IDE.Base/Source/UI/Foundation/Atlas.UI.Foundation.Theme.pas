unit Atlas.UI.Foundation.Theme;

// Themendienst der Atlas-Fenster (#2061): Farben, Dialogschrift und
// Themenwechsel an einer Stelle, statt dass jedes Fenster sie selbst holt
// (39 Units setzten die Schrift von Hand, 36 Dialoge hatten gar kein Thema,
// der mitlaufende Kopf hörte nicht auf den Wechsel, #2058).
// Die Schicht UI kennt die Open Tools API nicht. Die IDE-Schicht von Base
// setzt deshalb mit Install die Quelle der Farben (TAtlasIdeStyle.Colors) und
// das Anwenden des IDE-Themas auf ein Fenster (ApplyIdeTheme) und meldet mit
// Changed jeden Themenwechsel. Ohne Install (Tests, Werkzeuge) gelten die
// hellen Atlas-Farben, Apply tut nichts.
// Wer dem Thema folgt, meldet sich mit Subscribe an und spätestens im
// Destroy mit Unsubscribe ab; nach dem Abmelden erreicht ihn nichts mehr.
// Nur im Hauptthread.

interface

uses
  System.SysUtils,
  Vcl.Graphics,
  Vcl.Controls,
  Atlas.Core.Style.Palette,
  Atlas.Core.Style.Signal,
  Atlas.Core.Style.Listeners;

type
  TAtlasUiTheme = class
  public const
    /// <summary>Schrift der Atlas-Dialoge.</summary>
    cFontName = 'Segoe UI';
    cFontSize = 9;
  private
    class var FListeners: TAtlasThemeListeners;
    class var FColorSource: TFunc<TAtlasColors>;
    class var FApplier: TProc<TWinControl>;
    class var FOnFailure: TProc<string>;
    class function Listeners: TAtlasThemeListeners; static;
  public
    class constructor Create;
    class destructor Destroy;
    /// <summary>Quelle der Farben und Anwenden des IDE-Themas setzen (IDE-Schicht von Base, beim Start).
    /// AOnFailure bekommt Fehler von Abonnenten für das Protokoll; nil = verwerfen.</summary>
    class procedure Install(const AColorSource: TFunc<TAtlasColors>; const AApplier: TProc<TWinControl>;
      const AOnFailure: TProc<string>); static;
    /// <summary>Quelle und Anwenden wieder lösen (beim Entladen von Base); Abonnenten bleiben angemeldet.</summary>
    class procedure Uninstall; static;
    /// <summary>Aktuelle Atlas-Farben passend zum IDE-Thema; ohne Install die hellen.</summary>
    class function Colors: TAtlasColors; static;
    /// <summary>Textfarbe einer Meldung auf der Fensterfläche: Fehler, Warnung und Ok aus der Palette (für Text
    /// gedacht, nicht die Signalpunkte); Hinweis und ohne Aussage = Textfarbe des Stils (clWindowText).</summary>
    class function TextColor(AKind: TAtlasSignalKind): TColor; static;
    /// <summary>True, wenn TextColor(AKind) die Farbe des Stils ist (dann zeichnet der Stil die Schrift).</summary>
    class function UsesStyleText(AKind: TAtlasSignalKind): Boolean; static;
    /// <summary>Dialogschrift auf AFont übertragen (Name und Größe, Stil und Farbe bleiben).</summary>
    class procedure AssignDialogFont(AFont: TFont); static;
    /// <summary>IDE-Thema auf AControl und seine Kinder anwenden; ohne Install nichts.</summary>
    class procedure Apply(AControl: TWinControl); static;
    /// <summary>AHandler bei jedem Themenwechsel rufen, bis AOwner sich abmeldet.</summary>
    class procedure Subscribe(AOwner: TObject; const AHandler: TProc); static;
    class procedure Unsubscribe(AOwner: TObject); static;
    /// <summary>True, wenn AOwner angemeldet ist.</summary>
    class function Subscribed(AOwner: TObject): Boolean; static;
    /// <summary>Das IDE-Thema hat gewechselt: alle Abonnenten rufen.</summary>
    class procedure Changed; static;
  end;

implementation

{ TAtlasUiTheme }

class constructor TAtlasUiTheme.Create;
begin
  // Gleich anlegen statt beim ersten Abonnenten: Sonst bliebe die Liste ab dem ersten Atlas-Fenster bis zum
  // Entladen belegt, und der Leckmonitor der Tests rechnete sie diesem Fenster zu.
  FListeners := TAtlasThemeListeners.Create;
end;

class destructor TAtlasUiTheme.Destroy;
begin
  FreeAndNil(FListeners);
  FColorSource := nil;
  FApplier := nil;
  FOnFailure := nil;
end;

class function TAtlasUiTheme.Listeners: TAtlasThemeListeners;
begin
  if FListeners = nil then
  begin
    FListeners := TAtlasThemeListeners.Create;
  end;
  Result := FListeners;
end;

class procedure TAtlasUiTheme.Install(const AColorSource: TFunc<TAtlasColors>;
  const AApplier: TProc<TWinControl>; const AOnFailure: TProc<string>);
begin
  FColorSource := AColorSource;
  FApplier := AApplier;
  FOnFailure := AOnFailure;
end;

class procedure TAtlasUiTheme.Uninstall;
begin
  FColorSource := nil;
  FApplier := nil;
  FOnFailure := nil;
end;

class function TAtlasUiTheme.Colors: TAtlasColors;
begin
  if Assigned(FColorSource) then
  begin
    Exit(FColorSource());
  end;
  Result := TAtlasColors.Light;
end;

class function TAtlasUiTheme.UsesStyleText(AKind: TAtlasSignalKind): Boolean;
begin
  Result := (AKind = TAtlasSignalKind.Info) or (AKind = TAtlasSignalKind.Idle);
end;

class function TAtlasUiTheme.TextColor(AKind: TAtlasSignalKind): TColor;
var
  mColors: TAtlasColors;
begin
  if UsesStyleText(AKind) then
  begin
    Exit(clWindowText);
  end;
  mColors := Colors;
  case AKind of
    TAtlasSignalKind.Ok:
      Result := TColor(mColors.Add);
    TAtlasSignalKind.Warn:
      Result := TColor(mColors.Warn);
  else
    Result := TColor(mColors.Error);
  end;
end;

class procedure TAtlasUiTheme.AssignDialogFont(AFont: TFont);
begin
  if AFont = nil then
  begin
    Exit;
  end;
  AFont.Name := cFontName;
  AFont.Size := cFontSize;
end;

class procedure TAtlasUiTheme.Apply(AControl: TWinControl);
begin
  if (AControl <> nil) and Assigned(FApplier) then
  begin
    FApplier(AControl);
  end;
end;

class procedure TAtlasUiTheme.Subscribe(AOwner: TObject; const AHandler: TProc);
begin
  Listeners.Add(AOwner, AHandler);
end;

class procedure TAtlasUiTheme.Unsubscribe(AOwner: TObject);
begin
  if FListeners <> nil then
  begin
    FListeners.Remove(AOwner);
  end;
end;

class function TAtlasUiTheme.Subscribed(AOwner: TObject): Boolean;
begin
  Result := (FListeners <> nil) and FListeners.Contains(AOwner);
end;

class procedure TAtlasUiTheme.Changed;
var
  mFailure: string;
begin
  if FListeners = nil then
  begin
    Exit;
  end;
  for mFailure in FListeners.Notify do
  begin
    if Assigned(FOnFailure) then
    begin
      FOnFailure(mFailure);
    end;
  end;
end;

end.
