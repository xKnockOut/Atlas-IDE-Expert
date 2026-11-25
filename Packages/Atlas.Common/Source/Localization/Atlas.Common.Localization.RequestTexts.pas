unit Atlas.Common.Localization.RequestTexts;

// Gemeinsame Benutzertexte zu Anfragen in beiden Sprachen (#1458), die Host, MCP-Werkzeuge und Befehle gleich
// brauchen: fehlende Argumente einer Anfrage oder eines MCP-Werkzeugs, erlaubte Werte eines Arguments und
// „kein Projekt geladen“. Aufzählungen werden in der Sprache der Texte verbunden („a, b und c“ bzw.
// „a, b and c“), damit nicht jede Unit eigene Varianten je Anzahl braucht.

interface

type
  /// <summary>Gemeinsame Texte zu Anfragen in der aktuellen Sprache (TAtlasLocale).</summary>
  TRequestTexts = record
  public
    /// <summary>AItems verbunden mit Komma und zuletzt „und“ (AOr = False) bzw. „oder“.</summary>
    class function Joined(const AItems: array of string; AOr: Boolean): string; static;
    /// <summary>Fehlende Argumente, z. B. Argumente "uri" und "position" fehlen.</summary>
    class function Missing(const ANames: array of string): string; static;
    /// <summary>Erlaubte Werte des Arguments AName, z. B. "format" ist markdown oder json.</summary>
    class function Choice(const AName: string; const AChoices: array of string): string; static;
    /// <summary>Kein Projekt geladen.</summary>
    class function NoProject: string; static;
    /// <summary>Kein Projekt geladen; Datei angeben (MCP-Werkzeuge mit optionaler Datei).</summary>
    class function NoProjectGiveFile: string; static;
  end;

implementation

uses
  Atlas.Common.Localization.Texts;

type
{$SCOPEDENUMS ON}
  TRequestText = (AndWord, OrWord, MissingOne, MissingMany, Choice, NoProject, NoProjectGiveFile);
{$SCOPEDENUMS OFF}

const
  cTexts: array[TRequestText] of TAtlasText = (
    (De: 'und'; En: 'and'),
    (De: 'oder'; En: 'or'),
    (De: 'Argument %s fehlt'; En: 'Argument %s is missing'),
    (De: 'Argumente %s fehlen'; En: 'Arguments %s are missing'),
    (De: '"%s" ist %s'; En: '"%s" is %s'),
    (De: 'Kein Projekt geladen'; En: 'No project loaded'),
    (De: 'Kein Projekt geladen; Datei angeben'; En: 'No project loaded; specify a file'));

{ TRequestTexts }

class function TRequestTexts.Joined(const AItems: array of string; AOr: Boolean): string;
var
  mIndex: Integer;
  mLast: string;
begin
  Result := '';
  if Length(AItems) = 0 then
  begin
    Exit;
  end;
  mLast := cTexts[TRequestText.AndWord].Text;
  if AOr then
  begin
    mLast := cTexts[TRequestText.OrWord].Text;
  end;
  Result := AItems[0];
  for mIndex := 1 to High(AItems) do
  begin
    if mIndex = High(AItems) then
    begin
      Result := Result + ' ' + mLast + ' ' + AItems[mIndex];
    end
    else
    begin
      Result := Result + ', ' + AItems[mIndex];
    end;
  end;
end;

class function TRequestTexts.Missing(const ANames: array of string): string;
var
  mQuoted: TArray<string>;
  mIndex: Integer;
begin
  SetLength(mQuoted, Length(ANames));
  for mIndex := 0 to High(ANames) do
  begin
    mQuoted[mIndex] := '"' + ANames[mIndex] + '"';
  end;
  if Length(mQuoted) = 1 then
  begin
    Result := cTexts[TRequestText.MissingOne].Fmt([mQuoted[0]]);
  end
  else
  begin
    Result := cTexts[TRequestText.MissingMany].Fmt([Joined(mQuoted, False)]);
  end;
end;

class function TRequestTexts.Choice(const AName: string; const AChoices: array of string): string;
begin
  Result := cTexts[TRequestText.Choice].Fmt([AName, Joined(AChoices, True)]);
end;

class function TRequestTexts.NoProject: string;
begin
  Result := cTexts[TRequestText.NoProject].Text;
end;

class function TRequestTexts.NoProjectGiveFile: string;
begin
  Result := cTexts[TRequestText.NoProjectGiveFile].Text;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Localization.RequestTexts', cTexts);

end.
