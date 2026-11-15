unit Atlas.Core.Completion.EditorPlan;

// Entscheidungen der Vervollständigung im Editor (Atlas.IDE.Completion.Editor), ohne VCL und Open Tools API:
// welche Taste die Liste nimmt (Navigation, Kürzel Strg+Q/D/C, Alt+↑/↓, Alt+1…6, Strg+Leertaste), ob ein getipptes
// Zeichen übernimmt (Commit-Zeichen), Schlüssel und Überladung der Details, Hinweis „nicht verfügbar“ und das
// getippte Präfix.

{$SCOPEDENUMS ON}

interface

uses
  System.Classes,
  Atlas.Core.Completion.Contract,
  Atlas.Core.Completion.Controller;

type
  /// <summary>Kürzel in der offenen Liste.</summary>
  TAtlasCompletionCommand = (None, TogglePanel, CopyDoc, ToggleFavorite, PreviousOverload, NextOverload, SelectChip,
    RevealInaccessible);

  /// <summary>Zustand der Liste, den die Kürzel brauchen.</summary>
  TAtlasCompletionCommandState = record
    /// <summary>Liste sichtbar.</summary>
    Visible: Boolean;
    /// <summary>Favoriten möglich (#1012).</summary>
    HasFavorites: Boolean;
    /// <summary>Markierter Doku-Text im Detailfeld.</summary>
    HasDocText: Boolean;
    /// <summary>Gewählter Eintrag hat mehrere Überladungen.</summary>
    HasOverloads: Boolean;
    /// <summary>Filterchips eingeschaltet.</summary>
    ChipsEnabled: Boolean;
    /// <summary>Nicht erreichbare Einträge lassen sich zeigen.</summary>
    CanRevealInaccessible: Boolean;
  end;

  /// <summary>Was die Liste mit einer Navigationstaste macht.</summary>
  TAtlasCompletionKeyStep = (
    /// <summary>Taste nehmen.</summary>
    Take,
    /// <summary>Taste dem Editor lassen.</summary>
    Pass,
    /// <summary>Passive Liste schließen, Taste dem Editor lassen (Enter fügt die Zeile ein).</summary>
    CloseAndPass);

  TAtlasCompletionEditorPlan = record
  public const
    /// <summary>Tastencodes wie in Winapi.Windows.</summary>
    cVkTab = $09;
    cVkReturn = $0D;
    cVkEscape = $1B;
    cVkSpace = $20;
    cVkPrior = $21;
    cVkNext = $22;
    cVkEnd = $23;
    cVkHome = $24;
    cVkUp = $26;
    cVkDown = $28;
    /// <summary>Alt+1 bis Alt+6 wählen einen Filterchip.</summary>
    cChipCount = 6;
  public
    /// <summary>Navigationstaste zu AKey; False für andere Tasten.</summary>
    class function NavigationKey(AKey: Word; out ANavigation: TAtlasNavigationKey): Boolean; static;
    /// <summary>Kürzel AKey mit AShift; None, wenn die Liste es nicht nimmt.</summary>
    class function Command(AKey: Word; AShift: TShiftState; const AState: TAtlasCompletionCommandState):
      TAtlasCompletionCommand; static;
    /// <summary>Filterchip (0-basiert) zu Alt+1 bis Alt+6.</summary>
    class function ChipIndex(AKey: Word): Integer; static;
    /// <summary>Navigationstaste AKey: Leertaste nur im Mengenmodus, Enter schließt die passive Liste, sonst nur bei
    /// sichtbarer Liste (Esc auch bei leerer).</summary>
    class function KeyStep(AKey: TAtlasNavigationKey; AVisible, ASetMode, APassive, AEmpty: Boolean):
      TAtlasCompletionKeyStep; static;
    /// <summary>Übernimmt das eben getippte Zeichen ALineText[AIndex] („(“, „;“, „.“) den gewählten Eintrag? AIndex
    /// ist 1-basiert und muss direkt vor dem Cursor ACharacter stehen.</summary>
    class function CommitsOnCharacter(AEnabled: Boolean; const ALineText: string; AIndex, ACharacter: Integer;
      ACanCommit: Boolean): Boolean; static;
    /// <summary>Getipptes Präfix ab AWordStart bis ACharacter (0-basiert).</summary>
    class function Prefix(const ALineText: string; AWordStart, ACharacter: Integer): string; static;
    /// <summary>Schlüssel der Details eines Eintrags: neu, wenn ein anderer gewählt ist.</summary>
    class function DetailsKey(const AItem: TAtlasCompletionItem): string; static;
    /// <summary>Überladung nach AIndex um ADelta weiter, im Kreis über ACount.</summary>
    class function NextOverload(AIndex, ADelta, ACount: Integer): Integer; static;
    /// <summary>AItem mit den Daten der Überladung AIndex (0 = die erste, wie geliefert).</summary>
    class function OverloadItem(const AItem: TAtlasCompletionItem; AIndex: Integer): TAtlasCompletionItem; static;
    /// <summary>Hinweis „nicht verfügbar unter …“: nicht verfügbar mit Bedingung, außer der Plattform.</summary>
    class function ShowsAvailability(const AItem: TAtlasCompletionItem): Boolean; static;
  end;

implementation

uses
  System.SysUtils;

{ TAtlasCompletionEditorPlan }

class function TAtlasCompletionEditorPlan.NavigationKey(AKey: Word; out ANavigation: TAtlasNavigationKey): Boolean;
begin
  Result := True;
  ANavigation := TAtlasNavigationKey.Up;
  case AKey of
    cVkUp:
      ANavigation := TAtlasNavigationKey.Up;
    cVkDown:
      ANavigation := TAtlasNavigationKey.Down;
    cVkPrior:
      ANavigation := TAtlasNavigationKey.PageUp;
    cVkNext:
      ANavigation := TAtlasNavigationKey.PageDown;
    cVkHome:
      ANavigation := TAtlasNavigationKey.First;
    cVkEnd:
      ANavigation := TAtlasNavigationKey.Last;
    cVkReturn, cVkTab:
      ANavigation := TAtlasNavigationKey.Accept;
    cVkEscape:
      ANavigation := TAtlasNavigationKey.Cancel;
    cVkSpace:
      ANavigation := TAtlasNavigationKey.Toggle;
  else
    Result := False;
  end;
end;

function IsChipKey(AKey: Word): Boolean;
begin
  Result := (AKey >= Ord('1')) and (AKey < Ord('1') + TAtlasCompletionEditorPlan.cChipCount);
end;

function IsWanted(AKey: Word; AShift: TShiftState; const AState: TAtlasCompletionCommandState): Boolean;
begin
  Result := AState.Visible and (((AKey = Ord('Q')) and (AShift = [ssCtrl])) or
    ((AKey = Ord('D')) and (AShift = [ssCtrl]) and AState.HasFavorites) or
    ((AKey = Ord('C')) and (AShift = [ssCtrl]) and AState.HasDocText) or
    (((AKey = TAtlasCompletionEditorPlan.cVkUp) or (AKey = TAtlasCompletionEditorPlan.cVkDown)) and
      (AShift = [ssAlt]) and AState.HasOverloads) or
    (AState.ChipsEnabled and IsChipKey(AKey) and (AShift = [ssAlt])));
  // Nicht erreichbare Einträge zeigen (Strg+Leertaste) auch ohne sichtbare Liste.
  Result := Result or ((AKey = TAtlasCompletionEditorPlan.cVkSpace) and (AShift = [ssCtrl]) and
    AState.CanRevealInaccessible);
end;

class function TAtlasCompletionEditorPlan.Command(AKey: Word; AShift: TShiftState;
  const AState: TAtlasCompletionCommandState): TAtlasCompletionCommand;
begin
  Result := TAtlasCompletionCommand.None;
  if not IsWanted(AKey, AShift, AState) then
  begin
    Exit;
  end;
  if IsChipKey(AKey) then
  begin
    Exit(TAtlasCompletionCommand.SelectChip);
  end;
  case AKey of
    Ord('Q'):
      Result := TAtlasCompletionCommand.TogglePanel;
    Ord('C'):
      Result := TAtlasCompletionCommand.CopyDoc;
    Ord('D'):
      Result := TAtlasCompletionCommand.ToggleFavorite;
    cVkUp:
      Result := TAtlasCompletionCommand.PreviousOverload;
    cVkDown:
      Result := TAtlasCompletionCommand.NextOverload;
    cVkSpace:
      Result := TAtlasCompletionCommand.RevealInaccessible;
  end;
end;

class function TAtlasCompletionEditorPlan.ChipIndex(AKey: Word): Integer;
begin
  Result := AKey - Ord('1');
end;

class function TAtlasCompletionEditorPlan.KeyStep(AKey: TAtlasNavigationKey; AVisible, ASetMode, APassive,
  AEmpty: Boolean): TAtlasCompletionKeyStep;
var
  mTake: Boolean;
begin
  if AKey = TAtlasNavigationKey.Toggle then
  begin
    mTake := AVisible and ASetMode;
  end
  else if (AKey = TAtlasNavigationKey.Accept) and APassive then
  begin
    Exit(TAtlasCompletionKeyStep.CloseAndPass);
  end
  else
  begin
    mTake := AVisible or (AEmpty and (AKey = TAtlasNavigationKey.Cancel));
  end;
  if mTake then
  begin
    Result := TAtlasCompletionKeyStep.Take;
  end
  else
  begin
    Result := TAtlasCompletionKeyStep.Pass;
  end;
end;

class function TAtlasCompletionEditorPlan.CommitsOnCharacter(AEnabled: Boolean; const ALineText: string; AIndex,
  ACharacter: Integer; ACanCommit: Boolean): Boolean;
begin
  Result := AEnabled and (AIndex = ACharacter) and (AIndex >= 1) and (AIndex <= Length(ALineText)) and
    CharInSet(ALineText[AIndex], ['(', ';', '.']) and ACanCommit;
end;

class function TAtlasCompletionEditorPlan.Prefix(const ALineText: string; AWordStart, ACharacter: Integer): string;
begin
  Result := Copy(ALineText, AWordStart + 1, ACharacter - AWordStart);
end;

class function TAtlasCompletionEditorPlan.DetailsKey(const AItem: TAtlasCompletionItem): string;
begin
  Result := AItem.Name + #0 + AItem.ResolveData;
end;

class function TAtlasCompletionEditorPlan.NextOverload(AIndex, ADelta, ACount: Integer): Integer;
begin
  Result := 0;
  if ACount > 0 then
  begin
    Result := (AIndex + ADelta + ACount) mod ACount;
  end;
end;

class function TAtlasCompletionEditorPlan.OverloadItem(const AItem: TAtlasCompletionItem; AIndex: Integer):
  TAtlasCompletionItem;
begin
  Result := AItem;
  if (AIndex > 0) and (AIndex <= Length(AItem.OverloadData)) then
  begin
    Result.ResolveData := AItem.OverloadData[AIndex - 1];
  end;
end;

class function TAtlasCompletionEditorPlan.ShowsAvailability(const AItem: TAtlasCompletionItem): Boolean;
begin
  Result := AItem.Unavailable and (AItem.Condition <> '') and not SameText(AItem.Condition, 'platform');
end;

end.
