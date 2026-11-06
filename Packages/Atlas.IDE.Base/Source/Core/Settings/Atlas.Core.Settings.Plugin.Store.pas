unit Atlas.Core.Settings.Plugin.Store;

// Ablage der Plugin-Einstellungen (#227): Lese- und Schreibschnittstelle, der gemeinsame Weg von Laden und
// Speichern (TAtlasSettingsExchange) und Hilfen, die mehrere Bereiche brauchen (ADR 0017).

interface

const
  /// <summary>Werte von bookmarks.quick.scope (#1104) in der Reihenfolge der Optionsseite.</summary>
  AtlasQuickBookmarkScopes: array[0..1] of string = ('project', 'file');
  /// <summary>Werte von editor.methodPlacement (#660).</summary>
  AtlasMethodPlacements: array[0..2] of string = ('declaration', 'alphabetical', 'off');
  /// <summary>Werte von editor.regionFolds (#1814) in der Reihenfolge der Auswahl auf der Optionsseite und von
  /// TAtlasRegionFoldMode (Atlas.Core.Editor.RegionFolds).</summary>
  AtlasRegionFoldModes: array[0..3] of string = ('keep', 'collapse', 'expand', 'off');
  /// <summary>Höchstlänge der Texte unter issues.* (#765).</summary>
  MaxIssuesText = 200;
  /// <summary>Werte von tasks.beforeBuild (#900) wie TAtlasTasks.BeforeBuildNames, in der Reihenfolge der Auswahl
  /// im Optionsdialog; die Einstellungen kennen die Projektaufgaben nicht (A-09, sonst Feature-Zyklus, und Base
  /// nicht das Modul Build, #1455), der Test hält beide gleich.</summary>
  TasksBeforeBuildNames: array[0..2] of string = ('off', 'warn', 'block');

type
  /// <summary>Ablage für Einstellungen; Werte als ganze Zahlen (Wahrheitswerte 0/1).</summary>
  IAtlasSettingsStore = interface
    ['{4C8E2A17-9B3D-4F61-A5E2-7D0C1B9F3E84}']
    function ReadInteger(const AName: string; ADefault: Integer): Integer;
    procedure WriteInteger(const AName: string; AValue: Integer);
    function ReadString(const AName, ADefault: string): string;
    procedure WriteString(const AName, AValue: string);
  end;

  /// <summary>Ablage, die gespeicherte Namen kennt und entfernen kann (#1280): Grundlage der Übernahme umbenannter
  /// Einstellungen (x-renamedFrom im Plugin-Katalog).</summary>
  IAtlasSettingsNames = interface
    ['{6B2E9D41-7C3A-4F85-B1D6-0A8E5C2F9B73}']
    /// <summary>Steht unter AName ein Wert (gleich welcher Art)?</summary>
    function Contains(const AName: string): Boolean;
    /// <summary>Wert unter AName entfernen; ohne Wert nichts.</summary>
    procedure Remove(const AName: string);
  end;

  /// <summary>Liest oder schreibt Einstellungen über eine Ablage: Laden und Speichern eines Bereichs
  /// gehen über dieselbe Liste (Exchange), damit Name und Art jedes Werts nur einmal stehen.</summary>
  TAtlasSettingsExchange = record
  private
    FStore: IAtlasSettingsStore;
    FWriting: Boolean;
  public
    /// <summary>Liest; fehlt ein Wert in AStore, bleibt der bisherige (die Vorgabe).</summary>
    class function Reader(const AStore: IAtlasSettingsStore): TAtlasSettingsExchange; static;
    /// <summary>Schreibt jeden Wert nach AStore.</summary>
    class function Writer(const AStore: IAtlasSettingsStore): TAtlasSettingsExchange; static;
    /// <summary>Wahrheitswert unter AName (abgelegt als 0/1).</summary>
    procedure Flag(const AName: string; var AValue: Boolean);
    /// <summary>Ganze Zahl unter AName.</summary>
    procedure Number(const AName: string; var AValue: Integer);
    /// <summary>Text unter AName.</summary>
    procedure Text(const AName: string; var AValue: string);
    /// <summary>Text unter AName ohne Leerraum am Rand; beim Schreiben bleibt AValue unverändert.</summary>
    procedure TrimmedText(const AName: string; var AValue: string);
    /// <summary>Die Ablage, für Werte mit eigenem Übergang (z. B. umbenannte Namen).</summary>
    property Store: IAtlasSettingsStore read FStore;
    /// <summary>True beim Speichern, False beim Laden.</summary>
    property Writing: Boolean read FWriting;
  end;

/// <summary>Ohne Zeilenumbrüche und Steuerzeichen, höchstens MaxIssuesText Zeichen; ATrim kürzt Leerraum am Rand.
/// </summary>
function NormalizedIssuesText(const AText: string; ATrim: Boolean): string;
/// <summary>AValue, wenn er (ohne Groß-/Kleinschreibung) unter AAllowed steht, in deren Schreibweise;
/// sonst der erste erlaubte Wert.</summary>
function Choice(const AValue: string; const AAllowed: array of string): string;
/// <summary>1 für True, 0 für False (Ablage der Wahrheitswerte).</summary>
function BoolValue(AValue: Boolean): Integer;

implementation

uses
  System.SysUtils;

function NormalizedIssuesText(const AText: string; ATrim: Boolean): string;
var
  Index: Integer;
begin
  Result := AText;
  for Index := 1 to Length(Result) do
  begin
    if Ord(Result[Index]) < 32 then
    begin
      Result[Index] := ' ';
    end;
  end;
  if ATrim then
  begin
    Result := Trim(Result);
  end;
  if Length(Result) > MaxIssuesText then
  begin
    Result := Copy(Result, 1, MaxIssuesText);
  end;
end;

function Choice(const AValue: string; const AAllowed: array of string): string;
var
  Item: string;
begin
  for Item in AAllowed do
  begin
    if SameText(Trim(AValue), Item) then
    begin
      Exit(Item);
    end;
  end;
  Result := AAllowed[0];
end;

function BoolValue(AValue: Boolean): Integer;
begin
  if AValue then
  begin
    Result := 1;
  end
  else
  begin
    Result := 0;
  end;
end;

{ TAtlasSettingsExchange }

class function TAtlasSettingsExchange.Reader(const AStore: IAtlasSettingsStore): TAtlasSettingsExchange;
begin
  Result.FStore := AStore;
  Result.FWriting := False;
end;

class function TAtlasSettingsExchange.Writer(const AStore: IAtlasSettingsStore): TAtlasSettingsExchange;
begin
  Result.FStore := AStore;
  Result.FWriting := True;
end;

procedure TAtlasSettingsExchange.Flag(const AName: string; var AValue: Boolean);
begin
  if FWriting then
  begin
    FStore.WriteInteger(AName, BoolValue(AValue));
  end
  else
  begin
    AValue := FStore.ReadInteger(AName, BoolValue(AValue)) <> 0;
  end;
end;

procedure TAtlasSettingsExchange.Number(const AName: string; var AValue: Integer);
begin
  if FWriting then
  begin
    FStore.WriteInteger(AName, AValue);
  end
  else
  begin
    AValue := FStore.ReadInteger(AName, AValue);
  end;
end;

procedure TAtlasSettingsExchange.Text(const AName: string; var AValue: string);
begin
  if FWriting then
  begin
    FStore.WriteString(AName, AValue);
  end
  else
  begin
    AValue := FStore.ReadString(AName, AValue);
  end;
end;

procedure TAtlasSettingsExchange.TrimmedText(const AName: string; var AValue: string);
begin
  if FWriting then
  begin
    FStore.WriteString(AName, Trim(AValue));
  end
  else
  begin
    AValue := Trim(FStore.ReadString(AName, AValue));
  end;
end;

end.
