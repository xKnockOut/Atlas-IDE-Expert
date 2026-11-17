unit Atlas.Core.Notifications.MessageSink;

// Eine Zeile an den Empfänger, den der Besitzer beim Anlegen bekommt
// (Meldungsfenster der IDE, Zeile des Moduls). Viele Teile der Module hielten
// dafür einen TProc<string> und je eine eigene Methode Report, die nur prüfte,
// ob der Empfänger da ist. Der Datensatz ersetzt Feld und Methode: Ohne
// Empfänger und bei leerem Text geschieht nichts, Clear gibt den Empfänger
// (und was er einfängt) vor dem Abbau frei.

interface

uses
  System.SysUtils;

type
  /// <summary>Empfänger einer Meldungszeile, der fehlen darf.</summary>
  TAtlasMessageSink = record
  private
    FTarget: TProc<string>;
  public
    /// <summary>Sink für ATarget; nil ergibt einen Sink, der nichts tut.</summary>
    class function Create(const ATarget: TProc<string>): TAtlasMessageSink; static;
    /// <summary>AText an den Empfänger; nichts ohne Empfänger oder bei leerem Text.</summary>
    procedure Say(const AText: string);
    /// <summary>Empfänger loslassen; danach tut Say nichts.</summary>
    procedure Clear;
  end;

implementation

{ TAtlasMessageSink }

class function TAtlasMessageSink.Create(const ATarget: TProc<string>): TAtlasMessageSink;
begin
  Result.FTarget := ATarget;
end;

procedure TAtlasMessageSink.Say(const AText: string);
begin
  if Assigned(FTarget) and (AText <> '') then
  begin
    FTarget(AText);
  end;
end;

procedure TAtlasMessageSink.Clear;
begin
  FTarget := nil;
end;

end.
