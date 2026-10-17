unit Atlas.Core.Settings.OverviewKinds;

// Arten der Übersichtsleiste (#519) für editor.overviewRulerKinds:
// kommagetrennte Namen ("diagnostics,search,changes,breakpoints,bookmarks,
// cursor"); unbekannte fallen weg, die Reihenfolge ist fest. Liegt bei den
// Einstellungen, damit der Parser ohne den Editor-Kern auskommt; die Marken
// selbst rechnet Atlas.Core.Editor.Overview.

interface

type
{$SCOPEDENUMS ON}
  TAtlasOverviewKind = (Diagnostics, Search, Changes, Breakpoints, Bookmarks, Cursor);
{$SCOPEDENUMS OFF}
  TAtlasOverviewKinds = set of TAtlasOverviewKind;

  TAtlasOverviewKindNames = class
  public const
    All = [TAtlasOverviewKind.Diagnostics, TAtlasOverviewKind.Search, TAtlasOverviewKind.Changes,
      TAtlasOverviewKind.Breakpoints, TAtlasOverviewKind.Bookmarks, TAtlasOverviewKind.Cursor];
  public
    class function Name(AKind: TAtlasOverviewKind): string; static;
    class function Parse(const AText: string): TAtlasOverviewKinds; static;
    class function Text(AKinds: TAtlasOverviewKinds): string; static;
    /// <summary>Bekannte Namen in fester Reihenfolge, ohne Doppelte.</summary>
    class function Normalize(const AText: string): string; static;
  end;

implementation

uses
  System.SysUtils;

const
  Names: array[TAtlasOverviewKind] of string = ('diagnostics', 'search', 'changes', 'breakpoints', 'bookmarks',
    'cursor');

class function TAtlasOverviewKindNames.Name(AKind: TAtlasOverviewKind): string;
begin
  Result := Names[AKind];
end;

class function TAtlasOverviewKindNames.Parse(const AText: string): TAtlasOverviewKinds;
var
  Part: string;
  Kind: TAtlasOverviewKind;
begin
  Result := [];
  for Part in AText.Split([',', ';', ' ']) do
    for Kind := Low(TAtlasOverviewKind) to High(TAtlasOverviewKind) do
      if SameText(Trim(Part), Names[Kind]) then
        Include(Result, Kind);
end;

class function TAtlasOverviewKindNames.Text(AKinds: TAtlasOverviewKinds): string;
var
  Kind: TAtlasOverviewKind;
begin
  Result := '';
  for Kind := Low(TAtlasOverviewKind) to High(TAtlasOverviewKind) do
    if Kind in AKinds then
    begin
      if Result <> '' then
        Result := Result + ',';
      Result := Result + Names[Kind];
    end;
end;

class function TAtlasOverviewKindNames.Normalize(const AText: string): string;
begin
  Result := Text(Parse(AText));
end;

end.
