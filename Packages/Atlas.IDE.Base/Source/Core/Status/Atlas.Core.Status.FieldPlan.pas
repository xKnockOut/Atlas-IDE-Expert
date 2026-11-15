unit Atlas.Core.Status.FieldPlan;

// Entscheidungen des Atlas-Felds in der Statusleiste der Editorfenster
// (#591) ohne VCL und Open Tools API: Text der Plakette (#601), Tooltip mit
// Plakette, welche Zusatzfelder in der Statuszeile stehen (#575, #1777),
// was ein Linksklick auf eine Zone auslöst und welche Mausgeste die
// Schnellschalter öffnet (#604, statusField.toggles). Panels, Hooks und
// Zeichnen bleiben in Atlas.IDE.Status.Field.

{$SCOPEDENUMS ON}

interface

uses
  Atlas.Core.Settings.Plugin;

type
  /// <summary>Was ein Linksklick in der Statuszeile auslöst: nichts von Atlas; Liste der Benachrichtigungen
  /// (Plakette); Statusfenster; Zusatzfeld.</summary>
  TAtlasStatusFieldClick = (None, Badge, Window, Extra);

  /// <summary>Mausnachricht über der Statuszeile, nach der die Schnellschalter aufgehen können.</summary>
  TAtlasStatusFieldGesture = (RightButton, DoubleClick, ContextMenu);

  TAtlasStatusFieldPlan = record
  public const
    /// <summary>Höchste Zahl auf der Plakette; mehr steht als „99+“.</summary>
    cBadgeMax = 99;
  public
    /// <summary>Text der Plakette: die Zahl, ab cBadgeMax + 1 „99+“.</summary>
    class function BadgeText(ACount: Integer): string; static;
    /// <summary>Tooltip des Felds: ATooltip, mit Plakette (ABadgeCount > 0 und Hinweis) in einer eigenen Zeile
    /// dahinter.</summary>
    class function Tooltip(const ATooltip: string; ABadgeCount: Integer; const ABadgeHint: string): string; static;
    /// <summary>Atlas-Panel in der Statuszeile zeigen: statusField.enabled und nicht in die Atlas-Statusleiste
    /// umgezogen (ARelocated).</summary>
    class function PanelShown(const ASettings: TAtlasPluginSettings; ARelocated: Boolean): Boolean; static;
    /// <summary>Zusatzfelder in der Statuszeile: keine, wenn sie in der Atlas-Statusleiste stehen.</summary>
    class function ExtraPanels(AExtras: Integer; ARelocated: Boolean): Integer; static;
    /// <summary>Linksklick in Zone AZone (0 = Atlas-Feld, 1.. = Zusatzfeld, -1 = keins) bei AExtras Zusatzfeldern.
    /// Im Atlas-Feld gilt die Plakette, wenn sie Einträge hat (ABadgeCount), ein Ziel kennt (ABadgeClick) und AX
    /// rechts von ABadgeLeft liegt.</summary>
    class function Click(AZone, AExtras, ABadgeCount: Integer; ABadgeClick: Boolean;
      AX, ABadgeLeft: Integer): TAtlasStatusFieldClick; static;
    /// <summary>Öffnet AGesture über dem Atlas-Feld (AInPanel) die Schnellschalter? Nur mit Ziel (AHasContext) und
    /// nach statusField.toggles; das Kontextmenü von der Tastatur (AFromKeyboard) bleibt bei der IDE.</summary>
    class function OpensToggles(AGesture: TAtlasStatusFieldGesture; const ASettings: TAtlasPluginSettings;
      AHasContext, AInPanel, AFromKeyboard: Boolean): Boolean; static;
  end;

implementation

uses
  System.SysUtils;

{ TAtlasStatusFieldPlan }

class function TAtlasStatusFieldPlan.BadgeText(ACount: Integer): string;
begin
  if ACount > cBadgeMax then
  begin
    Result := IntToStr(cBadgeMax) + '+';
  end
  else
  begin
    Result := IntToStr(ACount);
  end;
end;

class function TAtlasStatusFieldPlan.Tooltip(const ATooltip: string; ABadgeCount: Integer;
  const ABadgeHint: string): string;
begin
  Result := ATooltip;
  if (ABadgeCount <= 0) or (ABadgeHint = '') then
  begin
    Exit;
  end;
  if Result <> '' then
  begin
    Result := Result + sLineBreak;
  end;
  Result := Result + ABadgeHint;
end;

class function TAtlasStatusFieldPlan.PanelShown(const ASettings: TAtlasPluginSettings; ARelocated: Boolean): Boolean;
begin
  Result := ASettings.StatusField and not ARelocated;
end;

class function TAtlasStatusFieldPlan.ExtraPanels(AExtras: Integer; ARelocated: Boolean): Integer;
begin
  Result := AExtras;
  if ARelocated then
  begin
    Result := 0;
  end;
end;

class function TAtlasStatusFieldPlan.Click(AZone, AExtras, ABadgeCount: Integer; ABadgeClick: Boolean;
  AX, ABadgeLeft: Integer): TAtlasStatusFieldClick;
begin
  if AZone = 0 then
  begin
    if (ABadgeCount > 0) and ABadgeClick and (AX >= ABadgeLeft) then
    begin
      Exit(TAtlasStatusFieldClick.Badge);
    end;
    Exit(TAtlasStatusFieldClick.Window);
  end;
  if (AZone > 0) and (AZone <= AExtras) then
  begin
    Exit(TAtlasStatusFieldClick.Extra);
  end;
  Result := TAtlasStatusFieldClick.None;
end;

class function TAtlasStatusFieldPlan.OpensToggles(AGesture: TAtlasStatusFieldGesture;
  const ASettings: TAtlasPluginSettings; AHasContext, AInPanel, AFromKeyboard: Boolean): Boolean;
begin
  Result := AHasContext and AInPanel;
  if not Result then
  begin
    Exit;
  end;
  case AGesture of
    TAtlasStatusFieldGesture.DoubleClick:
      Result := ASettings.StatusTogglesOnDoubleClick;
    TAtlasStatusFieldGesture.ContextMenu:
      Result := not AFromKeyboard and ASettings.StatusTogglesOnRightClick;
  else
    Result := ASettings.StatusTogglesOnRightClick;
  end;
end;

end.
