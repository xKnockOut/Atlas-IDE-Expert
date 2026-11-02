unit Atlas.Core.Settings.ToolbarItems;

// Atlas-Editorleiste (#1101), Belegung ohne VCL und OTA. Gehört zu den
// Einstellungen, weil der Parser (Atlas.Core.Settings.Plugin) die Liste
// bereinigt; die Symbole je Befehl stehen in Atlas.Core.EditorToolbar.Icons.
// - editor.toolbar.items ist eine Liste von Befehlskennungen der Befehlspalette
//   (#600), durch Komma getrennt; „|“ ist ein Trennstrich. Das Format ist so
//   angelegt, dass eigene Werkzeugleisten (#633) es wiederverwenden.
// - Parse liest die Liste, Normalize schreibt sie in einheitlicher Form:
//   ohne Leerraum, ohne leere Einträge, ohne doppelte Knöpfe, ohne Trennstriche
//   am Anfang, am Ende und doppelt. Eine leere Liste bleibt leer (alle Knöpfe
//   entfernt), Default ist die Vorgabe-Belegung.
// - Add, Remove und Move sind die Schritte des Dialogs „Leiste anpassen“.
// - Die Abschnittsbefehle (interface, implementation, uses, initialization)
//   am Anfang der Leiste wandern nie in das Überlaufmenü (PinnedCount).

interface

uses
  System.SysUtils;

type
  TAtlasToolbarItems = class
  public const
    Separator = '|';
    Delimiter = ',';
    GotoInterface = 'Atlas.GotoInterface';
    GotoImplementation = 'Atlas.GotoImplementation';
    GotoUses = 'Atlas.GotoUses';
    GotoInitialization = 'Atlas.GotoInitialization';
    ReturnFromSection = 'Atlas.ReturnFromSection';
    FindMethod = 'Atlas.FindMethod';
    CommandPalette = 'Atlas.CommandPalette';
    Customize = 'Atlas.EditorToolbarCustomize';
  public
    /// <summary>Kennungen in Reihenfolge, Trennstrich als Separator; ohne Leerraum und leere Einträge.</summary>
    class function Parse(const AText: string): TArray<string>; static;
    /// <summary>Liste als Text (Delimiter dazwischen).</summary>
    class function Format(const AItems: TArray<string>): string; static;
    /// <summary>Einheitliche Liste (siehe oben).</summary>
    class function Clean(const AItems: TArray<string>): TArray<string>; static;
    /// <summary>Clean über Parse und Format.</summary>
    class function Normalize(const AText: string): string; static;
    /// <summary>Vorgabe-Belegung als Text bzw. als Liste.</summary>
    class function DefaultText: string; static;
    class function Default: TArray<string>; static;
    class function IsSeparator(const AId: string): Boolean; static;
    /// <summary>Abschnittsbefehl (interface, implementation, uses, initialization)?</summary>
    class function IsSection(const AId: string): Boolean; static;
    /// <summary>Anzahl der Abschnittsbefehle am Anfang; sie wandern nie in den Überlauf.</summary>
    class function PinnedCount(const AItems: TArray<string>): Integer; static;
    /// <summary>AId vor AIndex einfügen (hinten bei AIndex außerhalb); ein Knopf steht nur einmal in der Leiste,
    /// Trennstriche beliebig oft. Liefert den Index des eingefügten Eintrags, -1 wenn AId schon da war.</summary>
    class function Add(var AItems: TArray<string>; const AId: string; AIndex: Integer): Integer; static;
    /// <summary>Eintrag AIndex entfernen; False außerhalb.</summary>
    class function Remove(var AItems: TArray<string>; AIndex: Integer): Boolean; static;
    /// <summary>Eintrag AIndex um ADelta verschieben (−1 hoch, +1 runter); liefert den neuen Index, AIndex, wenn
    /// es nicht geht.</summary>
    class function Move(var AItems: TArray<string>; AIndex, ADelta: Integer): Integer; static;
  end;

implementation

const
  DefaultItems: array[0..14] of string = (TAtlasToolbarItems.GotoInterface, TAtlasToolbarItems.GotoImplementation,
    TAtlasToolbarItems.Separator, 'Atlas.NavBack', 'Atlas.NavForward', 'Atlas.ToggleMethod', 'Atlas.SwitchTestUnit',
    TAtlasToolbarItems.Separator, 'Atlas.UnitSearch', TAtlasToolbarItems.FindMethod, TAtlasToolbarItems.Separator,
    'Atlas.CodeActions', 'Atlas.FormatCode', 'Atlas.ProblemsWindow', TAtlasToolbarItems.CommandPalette);

class function TAtlasToolbarItems.Parse(const AText: string): TArray<string>;
var
  Part: string;
begin
  Result := nil;
  for Part in AText.Split([Delimiter]) do
    if Trim(Part) <> '' then
      Result := Result + [Trim(Part)];
end;

class function TAtlasToolbarItems.Format(const AItems: TArray<string>): string;
begin
  Result := string.Join(Delimiter, AItems);
end;

class function TAtlasToolbarItems.IsSeparator(const AId: string): Boolean;
begin
  Result := AId = Separator;
end;

class function TAtlasToolbarItems.Clean(const AItems: TArray<string>): TArray<string>;
var
  Item: string;
  Index: Integer;
  Seen: Boolean;
begin
  Result := nil;
  for Item in AItems do
  begin
    if Trim(Item) = '' then
      Continue;
    if IsSeparator(Item) then
    begin
      // Kein Trennstrich am Anfang und keiner doppelt.
      if (Length(Result) = 0) or IsSeparator(Result[High(Result)]) then
        Continue;
    end
    else
    begin
      Seen := False;
      for Index := 0 to High(Result) do
        if SameText(Result[Index], Item) then
          Seen := True;
      if Seen then
        Continue;
    end;
    Result := Result + [Trim(Item)];
  end;
  if (Length(Result) > 0) and IsSeparator(Result[High(Result)]) then
    SetLength(Result, Length(Result) - 1);
end;

class function TAtlasToolbarItems.Normalize(const AText: string): string;
begin
  Result := Format(Clean(Parse(AText)));
end;

class function TAtlasToolbarItems.Default: TArray<string>;
var
  Index: Integer;
begin
  SetLength(Result, Length(DefaultItems));
  for Index := 0 to High(DefaultItems) do
    Result[Index] := DefaultItems[Index];
end;

class function TAtlasToolbarItems.DefaultText: string;
begin
  Result := Format(Default);
end;

class function TAtlasToolbarItems.IsSection(const AId: string): Boolean;
begin
  Result := SameText(AId, GotoInterface) or SameText(AId, GotoImplementation) or SameText(AId, GotoUses) or
    SameText(AId, GotoInitialization);
end;

class function TAtlasToolbarItems.PinnedCount(const AItems: TArray<string>): Integer;
begin
  Result := 0;
  while (Result <= High(AItems)) and IsSection(AItems[Result]) do
    Inc(Result);
end;

class function TAtlasToolbarItems.Add(var AItems: TArray<string>; const AId: string; AIndex: Integer): Integer;
var
  Index: Integer;
begin
  Result := -1;
  if Trim(AId) = '' then
    Exit;
  if not IsSeparator(AId) then
    for Index := 0 to High(AItems) do
      if SameText(AItems[Index], AId) then
        Exit;
  if (AIndex < 0) or (AIndex > Length(AItems)) then
    AIndex := Length(AItems);
  Insert(AId, AItems, AIndex);
  Result := AIndex;
end;

class function TAtlasToolbarItems.Remove(var AItems: TArray<string>; AIndex: Integer): Boolean;
begin
  Result := (AIndex >= 0) and (AIndex <= High(AItems));
  if Result then
    Delete(AItems, AIndex, 1);
end;

class function TAtlasToolbarItems.Move(var AItems: TArray<string>; AIndex, ADelta: Integer): Integer;
var
  Target: Integer;
  Item: string;
begin
  Result := AIndex;
  Target := AIndex + ADelta;
  if (AIndex < 0) or (AIndex > High(AItems)) or (Target < 0) or (Target > High(AItems)) then
    Exit;
  Item := AItems[AIndex];
  AItems[AIndex] := AItems[Target];
  AItems[Target] := Item;
  Result := Target;
end;

end.
