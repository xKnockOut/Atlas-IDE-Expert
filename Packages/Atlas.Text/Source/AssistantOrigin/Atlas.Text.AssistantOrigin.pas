unit Atlas.Text.AssistantOrigin;

// Herkunft eines Auftrags von einem KI-Assistenten an die IDE (#2616), gemeinsam für MCP-Server und Plugin: Name
// des MCP-Clients (clientInfo.name, Freitext des Clients) und kurze Kennung des MCP-Prozesses (TIndexProcessInfo.
// SessionOf). Der MCP-Server schreibt beide in jeden Auftrag an die Eingänge des Plugins (Bearbeiten, Bauen,
// Debuggen, Fragen) als
//   "client": Name, "session": Kennung
// Fehlen sie (älterer Server), gilt der Auftrag als vom unbekannten Assistenten. Angezeigt wird gekürzt und ohne
// Steuerzeichen: „Assistent A · 3f2a“. Zwei Prozesse desselben Clients unterscheidet die Sitzung, zwei Clients
// zusätzlich der Name.

interface

uses
  System.JSON;

type
  TAtlasAssistantOrigin = record
  public const
    /// <summary>Höchstlänge des angezeigten Namens; länger wird mit „…“ gekürzt.</summary>
    cMaxClient = 40;
    /// <summary>Höchstlänge der Sitzungskennung.</summary>
    cMaxSession = 8;
    cSeparator = ' · ';
  public
    /// <summary>Name des MCP-Clients; '' unbekannt.</summary>
    Client: string;
    /// <summary>Kennung des MCP-Prozesses; '' unbekannt.</summary>
    Session: string;
    /// <summary>Herkunft mit bereinigtem Namen und bereinigter Kennung (Clean, CleanSession).</summary>
    class function Make(const AClient, ASession: string): TAtlasAssistantOrigin; static;
    /// <summary>Steuerzeichen werden zu Leerzeichen, Leerraum zusammengefasst, außen gekürzt; über AMax Zeichen mit
    /// „…“ am Ende.</summary>
    class function Clean(const AText: string; AMax: Integer): string; static;
    /// <summary>Nur Buchstaben, Ziffern und „-“, höchstens cMaxSession Zeichen.</summary>
    class function CleanSession(const AText: string): string; static;
    /// <summary>"client" und "session" aus AObject (bereinigt); fehlen sie oder ist AObject nil, bleiben sie ''.
    /// </summary>
    class function Read(AObject: TJSONObject): TAtlasAssistantOrigin; static;
    /// <summary>Schreibt "client" und "session" nach AObject, soweit bekannt.</summary>
    procedure AddTo(AObject: TJSONObject);
    /// <summary>Name oder Sitzung bekannt.</summary>
    function IsKnown: Boolean;
    /// <summary>Gleicher Assistent: gleiche Sitzung, ohne Sitzung gleicher Name.</summary>
    function SameAs(const AOther: TAtlasAssistantOrigin): Boolean;
    /// <summary>„Name · Kennung“; ohne Namen AUnknown, ohne Kennung nur der Name.</summary>
    function Caption(const AUnknown: string): string;
    /// <summary>Wie Caption, aber '' ganz ohne Herkunft (Texte, die dann wie bisher lauten).</summary>
    function Display(const AUnknown: string): string;
  end;

implementation

uses
  System.SysUtils;

{ TAtlasAssistantOrigin }

class function TAtlasAssistantOrigin.Make(const AClient, ASession: string): TAtlasAssistantOrigin;
begin
  Result.Client := Clean(AClient, cMaxClient);
  Result.Session := CleanSession(ASession);
end;

const
  cFirstPrintable = 32;
  cDelete = $7F;
  cLastC1 = $9F;
  cLineSeparator = $2028;
  cParagraphSeparator = $2029;

/// <summary>Steuerzeichen (C0, DEL, C1) und Zeilen- bzw. Absatztrenner.</summary>
function IsControl(AChar: Char): Boolean;
begin
  Result := (Ord(AChar) < cFirstPrintable) or ((Ord(AChar) >= cDelete) and (Ord(AChar) <= cLastC1)) or
    (Ord(AChar) = cLineSeparator) or (Ord(AChar) = cParagraphSeparator);
end;

class function TAtlasAssistantOrigin.Clean(const AText: string; AMax: Integer): string;
var
  mBuilder: TStringBuilder;
  mChar: Char;
  mSpace: Boolean;
begin
  mBuilder := TStringBuilder.Create;
  try
    mSpace := False;
    for mChar in AText do
    begin
      if IsControl(mChar) or (mChar = ' ') then
      begin
        mSpace := mBuilder.Length > 0;
        Continue;
      end;
      if mSpace then
      begin
        mBuilder.Append(' ');
        mSpace := False;
      end;
      mBuilder.Append(mChar);
    end;
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
  if (AMax > 1) and (Length(Result) > AMax) then
  begin
    Result := TrimRight(Copy(Result, 1, AMax - 1)) + '…';
  end;
end;

class function TAtlasAssistantOrigin.CleanSession(const AText: string): string;
var
  mChar: Char;
begin
  Result := '';
  for mChar in AText do
  begin
    if CharInSet(mChar, ['0'..'9', 'a'..'z', 'A'..'Z', '-']) and (Length(Result) < cMaxSession) then
    begin
      Result := Result + mChar;
    end;
  end;
end;

class function TAtlasAssistantOrigin.Read(AObject: TJSONObject): TAtlasAssistantOrigin;
begin
  Result := Default(TAtlasAssistantOrigin);
  if AObject = nil then
  begin
    Exit;
  end;
  Result := Make(AObject.GetValue<string>('client', ''), AObject.GetValue<string>('session', ''));
end;

procedure TAtlasAssistantOrigin.AddTo(AObject: TJSONObject);
begin
  if Client <> '' then
  begin
    AObject.AddPair('client', Client);
  end;
  if Session <> '' then
  begin
    AObject.AddPair('session', Session);
  end;
end;

function TAtlasAssistantOrigin.IsKnown: Boolean;
begin
  Result := (Client <> '') or (Session <> '');
end;

function TAtlasAssistantOrigin.SameAs(const AOther: TAtlasAssistantOrigin): Boolean;
begin
  if (Session <> '') or (AOther.Session <> '') then
  begin
    Result := SameText(Session, AOther.Session);
  end
  else
  begin
    Result := Client = AOther.Client;
  end;
end;

function TAtlasAssistantOrigin.Caption(const AUnknown: string): string;
begin
  Result := Client;
  if Result = '' then
  begin
    Result := AUnknown;
  end;
  if Session <> '' then
  begin
    Result := Result + cSeparator + Session;
  end;
end;

function TAtlasAssistantOrigin.Display(const AUnknown: string): string;
begin
  Result := '';
  if IsKnown then
  begin
    Result := Caption(AUnknown);
  end;
end;

end.
