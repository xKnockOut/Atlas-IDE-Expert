unit Atlas.UI.Foundation.ListBox;

// Liste (TListBox) für Atlas-Fenster, die beim Neuzeichnen nicht flackert.
// Unter dem Thema der IDE hängt an jeder TListBox ein Stil. Der zeichnet die
// ganze Liste neu, sobald sie den Fokus bekommt oder verliert (Klick in die
// Liste, Sprung in den Editor nach der Auswahl), und füllt dabei zuerst die
// ganze Fläche in der Grundfarbe; danach kommen die Zeilen: Die Liste blitzt
// kurz leer auf.
// TAtlasListBox beantwortet WM_ERASEBKGND selbst, bevor der Stil es sieht
// (WndProc), und füllt nur die Fläche, auf die keine Zeile kommt: unter der
// letzten Zeile, ohne Zeilen die ganze Liste. Die Zeilen malen ihr Rechteck
// selbst ganz aus. So wird nichts doppelt gemalt, mit oder ohne Puffer, und
// die Liste hängt nicht davon ab, ob und wie die VCL in einen Puffer löscht.
// Gefüllt wird mit dem Pinsel der Liste (Color).

interface

uses
  Winapi.Windows,
  Winapi.Messages,
  System.Types,
  Vcl.StdCtrls;

type
  TAtlasListBox = class(TListBox)
  private
    procedure EraseOutsideRows(ADC: HDC);
  protected
    /// <summary>WM_ERASEBKGND selbst beantworten: nur die Fläche ohne Zeilen füllen.</summary>
    procedure WndProc(var Message: TMessage); override;
  public
    /// <summary>Fläche, auf die keine Zeile kommt (unter der letzten Zeile); leer, wenn die Zeilen die Liste
    /// füllen.</summary>
    function FreeArea: TRect;
  end;

implementation

{ TAtlasListBox }

function TAtlasListBox.FreeArea: TRect;
var
  mBottom: Integer;
begin
  Result := ClientRect;
  if Count = 0 then
  begin
    Exit;
  end;
  // ItemRect kennt auch Zeilen unterhalb des sichtbaren Bereichs; dann ist nichts frei.
  mBottom := ItemRect(Count - 1).Bottom;
  if mBottom >= Result.Bottom then
  begin
    Result := TRect.Empty;
    Exit;
  end;
  if mBottom > Result.Top then
  begin
    Result.Top := mBottom;
  end;
end;

procedure TAtlasListBox.EraseOutsideRows(ADC: HDC);
var
  mArea: TRect;
begin
  mArea := FreeArea;
  if not mArea.IsEmpty then
  begin
    FillRect(ADC, mArea, Brush.Handle);
  end;
end;

procedure TAtlasListBox.WndProc(var Message: TMessage);
begin
  // Vor inherited: Dort sieht der Stil der IDE die Nachricht zuerst und füllte die ganze Fläche.
  if (Message.Msg = WM_ERASEBKGND) and HandleAllocated then
  begin
    EraseOutsideRows(HDC(Message.WParam));
    Message.Result := 1;
    Exit;
  end;
  inherited WndProc(Message);
end;

end.
