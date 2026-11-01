unit Atlas.Core.Outline.NavigationOption;

// Navigationsleiste der IDE über ihre eigene Option ausblenden (Bericht M3,
// editor.breadcrumbsHideIdeToolbar): RAD Studio hat unter Tools › Optionen ›
// Editor › Anzeige „Navigationssymbolleiste anzeigen“. Bisher hängte Atlas
// die Leiste in ein eigenes Panel um, weil die IDE Visible bei jedem Reiter
// neu setzt; das ist ein Eingriff in das Editorfenster der IDE (Hänger
// #1093, Verdacht bei der Zugriffsverletzung beim Beenden). Jetzt schaltet
// Atlas die Option der IDE, und die IDE blendet die Leiste selbst aus.
// - Find sucht den Namen der Option unter den Optionsnamen der IDE
//   (IOTAEnvironmentOptions.GetOptionNames): enthält „Nav“ und „Bar“,
//   bevorzugt mit „Show“ bzw. „Visible“. Den genauen Namen nennt die Open
//   Tools API nicht; er steht nach dem ersten Lauf im atlas.log.
// - Candidates nennt fürs Protokoll alle Namen mit „Nav“ oder „Toolbar“,
//   wenn Find nichts findet.
// - IsOn und Encode lesen und schreiben den Wert in der Art, in der die IDE
//   ihn liefert (Boolean, Zahl oder Text).
// Ohne VCL und Open Tools API.

interface

uses
  System.Variants;

type
  TAtlasNavigationOption = class
  public
    /// <summary>Name der IDE-Option „Navigationssymbolleiste anzeigen“ unter ANames; '' = keine.</summary>
    class function Find(const ANames: TArray<string>): string; static;
    /// <summary>Namen, die nach Navigation oder Werkzeugleiste klingen (Protokoll, wenn Find nichts findet).</summary>
    class function Candidates(const ANames: TArray<string>): TArray<string>; static;
    /// <summary>Wert der Option als Schalter; leer oder unlesbar gilt die Vorgabe der IDE: an.</summary>
    class function IsOn(const AValue: Variant): Boolean; static;
    /// <summary>AOn in der Art von AOld (Boolean, Zahl oder Text 'True'/'False').</summary>
    class function Encode(const AOld: Variant; AOn: Boolean): Variant; static;
  end;

implementation

uses
  System.SysUtils;

class function TAtlasNavigationOption.Find(const ANames: TArray<string>): string;
var
  Name, Key: string;
begin
  Result := '';
  for Name in ANames do
  begin
    Key := UpperCase(Name);
    if (Pos('NAV', Key) = 0) or (Pos('BAR', Key) = 0) then
      Continue;
    if (Pos('SHOW', Key) > 0) or (Pos('VISIBLE', Key) > 0) then
      Exit(Name);
    if Result = '' then
      Result := Name;
  end;
end;

class function TAtlasNavigationOption.Candidates(const ANames: TArray<string>): TArray<string>;
var
  Name, Key: string;
begin
  Result := nil;
  for Name in ANames do
  begin
    Key := UpperCase(Name);
    if (Pos('NAV', Key) > 0) or (Pos('TOOLBAR', Key) > 0) then
      Result := Result + [Name];
  end;
end;

class function TAtlasNavigationOption.IsOn(const AValue: Variant): Boolean;
begin
  Result := True;
  if VarIsNull(AValue) or VarIsEmpty(AValue) then
    Exit;
  if VarIsType(AValue, varBoolean) then
    Result := Boolean(AValue)
  else if VarIsOrdinal(AValue) then
    Result := Int64(AValue) <> 0
  else if VarIsStr(AValue) then
    Result := not (SameText(Trim(VarToStr(AValue)), 'False') or (Trim(VarToStr(AValue)) = '0'));
end;

class function TAtlasNavigationOption.Encode(const AOld: Variant; AOn: Boolean): Variant;
begin
  if VarIsOrdinal(AOld) and not VarIsType(AOld, varBoolean) then
    Result := Ord(AOn)
  else if VarIsStr(AOld) then
    Result := BoolToStr(AOn, True)
  else
    Result := AOn;
end;

end.
