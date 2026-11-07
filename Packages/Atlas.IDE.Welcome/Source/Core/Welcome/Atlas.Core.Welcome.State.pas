unit Atlas.Core.Welcome.State;

// Zustandskachel „Atlas“ der Willkommensseite (#754), ohne VCL und Open Tools
// API: fünf Zeilen Server, Version, Index, Einrichtung und Diagnosemodus mit
// Ampelpunkt, Text und Zusatz rechts, darunter die Knöpfe.
// - Die Zeilen kommen aus denselben Anbietern wie das Atlas-Statusfeld (#591):
//   Rows liest die Zeilen der Registry über ihre Kennung. Zustand und Aktion
//   sind die der Statusfeld-Zeile, der Text ihre Kurzform (IAtlasStatusBrief)
//   oder ihr Text. Kachel und Statusfeld können so keine verschiedene Ampel
//   zeigen.
// - Fehlt eine Zeile im Statusfeld (Diagnosemodus aus, Einrichtung noch nicht
//   geprüft, abgesicherter Start ohne Update-Prüfung …), steht in der Kachel
//   eine neutrale Ersatzzeile (Present = False); den Text wählt die UI.
// - Visible: welcomePage.statusTile und welcomePage.statusTile.onlyProblems
//   (nur zeigen, wenn eine Zeile gelb oder rot ist).
// - Buttons: „Server neu starten“, „Einstellungen“, „Log-Ordner öffnen“, bei
//   bereitstehendem Update (Zeile „Version“ gelb) „Jetzt aktualisieren“.
// - Signature: ändert sich nur, wenn sich in der Kachel etwas Sichtbares
//   ändert; danach wird neu gezeichnet (Invalidate), nicht per Zeitgeber.

interface

uses
  System.SysUtils,
  Atlas.Core.Status.Contract;

type
{$SCOPEDENUMS ON}
  TAtlasStateRowKind = (Server, Version, Index, Setup, Diagnostic);
  TAtlasStateButton = (Restart, Settings, LogFolder, Update);
{$SCOPEDENUMS OFF}

  TAtlasStateRow = record
    Kind: TAtlasStateRowKind;
    /// <summary>Kennung der Zeile im Statusfeld, z. B. "atlas.server".</summary>
    Id: string;
    /// <summary>Die Zeile gibt es im Statusfeld; sonst Ersatzzeile (neutral, Text von der UI).</summary>
    Present: Boolean;
    State: TAtlasStatusState;
    /// <summary>Kurzform der Zeile, sonst ihr Text; '' bei Ersatzzeilen.</summary>
    Text: string;
    /// <summary>Zusatz rechts; '' = keiner.</summary>
    Detail: string;
    /// <summary>Voller Text der Zeile im Statusfeld (Tooltip).</summary>
    Hint: string;
    /// <summary>Klick auf die Zeile führt die Aktion der Statusfeld-Zeile aus.</summary>
    HasAction: Boolean;
  end;

  TAtlasStateRows = TArray<TAtlasStateRow>;

  TAtlasWelcomeState = class
  public
    /// <summary>Kennung der Statusfeld-Zeile je Art.</summary>
    class function IdOf(AKind: TAtlasStateRowKind): string; static;
    /// <summary>Die fünf Zeilen in fester Reihenfolge aus den Zeilen des Statusfelds (#591).</summary>
    class function Rows(const AItems: TArray<IAtlasStatusItem>): TAtlasStateRows; static;
    /// <summary>Schlechtester Zustand der Zeilen; Neutral ohne Zeilen.</summary>
    class function Overall(const ARows: TAtlasStateRows): TAtlasStatusState; static;
    /// <summary>Eine Zeile ist gelb oder rot.</summary>
    class function HasProblem(const ARows: TAtlasStateRows): Boolean; static;
    /// <summary>Kachel zeigen: AEnabled (welcomePage.statusTile) und, mit AOnlyProblems
    /// (welcomePage.statusTile.onlyProblems), nur bei einer gelben oder roten Zeile.</summary>
    class function Visible(AEnabled, AOnlyProblems: Boolean; const ARows: TAtlasStateRows): Boolean; static;
    /// <summary>Ein Update steht bereit: Zeile „Version“ ist gelb.</summary>
    class function UpdateReady(const ARows: TAtlasStateRows): Boolean; static;
    /// <summary>Knöpfe unter den Zeilen; „Jetzt aktualisieren“ nur mit UpdateReady.</summary>
    class function Buttons(const ARows: TAtlasStateRows): TArray<TAtlasStateButton>; static;
    /// <summary>Fingerabdruck alles Sichtbaren (Zustand, Text, Zusatz, Tooltip, Aktion je Zeile).</summary>
    class function Signature(const ARows: TAtlasStateRows): string; static;
  end;

implementation

uses
  Atlas.Core.Status.Lines;

{ TAtlasWelcomeState }

class function TAtlasWelcomeState.IdOf(AKind: TAtlasStateRowKind): string;
begin
  case AKind of
    TAtlasStateRowKind.Server:
      Result := TAtlasStatusLines.ServerId;
    TAtlasStateRowKind.Version:
      Result := TAtlasStatusLines.VersionId;
    TAtlasStateRowKind.Index:
      Result := TAtlasStatusLines.IndexId;
    TAtlasStateRowKind.Setup:
      Result := TAtlasStatusLines.SetupId;
  else
    Result := TAtlasStatusLines.DiagnosticModeId;
  end;
end;

function FindItem(const AItems: TArray<IAtlasStatusItem>; const AId: string): IAtlasStatusItem;
var
  mItem: IAtlasStatusItem;
begin
  Result := nil;
  for mItem in AItems do
  begin
    if (mItem <> nil) and SameText(mItem.Id, AId) then
    begin
      Exit(mItem);
    end;
  end;
end;

class function TAtlasWelcomeState.Rows(const AItems: TArray<IAtlasStatusItem>): TAtlasStateRows;
var
  mKind: TAtlasStateRowKind;
  mItem: IAtlasStatusItem;
  mBrief: IAtlasStatusBrief;
  mRow: TAtlasStateRow;
begin
  // Ergebnis leeren: Ein dynamisches Array als Result kann beim Eintritt Inhalt des Ziels tragen.
  Result := nil;
  for mKind := Low(TAtlasStateRowKind) to High(TAtlasStateRowKind) do
  begin
    mRow := Default(TAtlasStateRow);
    mRow.Kind := mKind;
    mRow.Id := IdOf(mKind);
    mRow.State := TAtlasStatusState.Neutral;
    mItem := FindItem(AItems, mRow.Id);
    if mItem <> nil then
    begin
      mRow.Present := True;
      // Zustand und Aktion genau wie im Statusfeld.
      mRow.State := mItem.State;
      mRow.HasAction := mItem.HasAction;
      mRow.Hint := mItem.Text;
      mRow.Text := mItem.Text;
      if Supports(mItem, IAtlasStatusBrief, mBrief) then
      begin
        if mBrief.Brief <> '' then
        begin
          mRow.Text := mBrief.Brief;
        end;
        mRow.Detail := mBrief.Detail;
      end;
    end;
    Result := Result + [mRow];
  end;
end;

class function TAtlasWelcomeState.Overall(const ARows: TAtlasStateRows): TAtlasStatusState;
var
  mRow: TAtlasStateRow;
begin
  Result := TAtlasStatusState.Neutral;
  for mRow in ARows do
  begin
    if Ord(mRow.State) > Ord(Result) then
    begin
      Result := mRow.State;
    end;
  end;
end;

class function TAtlasWelcomeState.HasProblem(const ARows: TAtlasStateRows): Boolean;
begin
  Result := Ord(Overall(ARows)) >= Ord(TAtlasStatusState.Yellow);
end;

class function TAtlasWelcomeState.Visible(AEnabled, AOnlyProblems: Boolean; const ARows: TAtlasStateRows): Boolean;
begin
  Result := AEnabled and (not AOnlyProblems or HasProblem(ARows));
end;

class function TAtlasWelcomeState.UpdateReady(const ARows: TAtlasStateRows): Boolean;
var
  mRow: TAtlasStateRow;
begin
  Result := False;
  for mRow in ARows do
  begin
    if (mRow.Kind = TAtlasStateRowKind.Version) and mRow.Present and (mRow.State = TAtlasStatusState.Yellow) then
    begin
      Exit(True);
    end;
  end;
end;

class function TAtlasWelcomeState.Buttons(const ARows: TAtlasStateRows): TArray<TAtlasStateButton>;
begin
  // Einzeln zuweisen: Eine Liste von Aufzählungswerten in eckigen Klammern liest der Compiler als Menge.
  SetLength(Result, 3);
  Result[0] := TAtlasStateButton.Restart;
  Result[1] := TAtlasStateButton.Settings;
  Result[2] := TAtlasStateButton.LogFolder;
  if UpdateReady(ARows) then
  begin
    SetLength(Result, 4);
    Result[3] := TAtlasStateButton.Update;
  end;
end;

class function TAtlasWelcomeState.Signature(const ARows: TAtlasStateRows): string;
var
  mRow: TAtlasStateRow;
begin
  Result := '';
  for mRow in ARows do
  begin
    Result := Result + Format('%d|%d|%d|%d|%s|%s|%s'#10, [Ord(mRow.Kind), Ord(mRow.Present), Ord(mRow.State),
      Ord(mRow.HasAction), mRow.Text, mRow.Detail, mRow.Hint]);
  end;
end;

end.
