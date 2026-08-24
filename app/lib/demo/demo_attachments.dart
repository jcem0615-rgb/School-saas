/// Real files for the demo's coursework, inlined.
///
/// Demo mode never touches Storage, so a seeded attachment cannot be a
/// download URL. It used to be a plausible-looking https address at
/// example.org, and that was worse than nothing: a student tapped the one
/// piece of material on the screen and got a dead link, which reads as a
/// broken app rather than as a demo without a bucket behind it.
///
/// These are genuine one-page PDFs -- the actual problem set, the actual
/// quiz -- carried as data URIs so they open with no network at all. See
/// openAttachment() for how a data URI is handed to the platform, since
/// browsers refuse to navigate to one.
class DemoAttachments {
  DemoAttachments._();

  /// Ten quadratic-equation items, the assignment a Grade 10 class is
  /// actually working on in this demo.
  static const problemSet4 =
      'data:application/pdf;base64,JVBERi0xLjQKMSAwIG9iago8PCAvVHlwZSAvQ2F0YWxvZyAvUGFnZXMgMi'
      'AwIFIgPj4KZW5kb2JqCjIgMCBvYmoKPDwgL1R5cGUgL1BhZ2VzIC9LaWRzIFszIDAgUl0gL0NvdW50IDEgPj4K'
      'ZW5kb2JqCjMgMCBvYmoKPDwgL1R5cGUgL1BhZ2UgL1BhcmVudCAyIDAgUiAvTWVkaWFCb3ggWzAgMCA2MTIgNz'
      'kyXSAvUmVzb3VyY2VzIDw8IC9Gb250IDw8IC9GMSA1IDAgUiA+PiA+PiAvQ29udGVudHMgNCAwIFIgPj4KZW5k'
      'b2JqCjQgMCBvYmoKPDwgL0xlbmd0aCA5OTEgPj4Kc3RyZWFtCkJUCi9GMSAxNiBUZgo2MCA3NjAgVGQKKFF1YW'
      'RyYXRpYyBFcXVhdGlvbnMgLSBQcm9ibGVtIFNldCA0KSBUagovRjEgMTEgVGYKMCAtMjggVGQKKEFuc3dlciBh'
      'bGwgdGVuIGl0ZW1zLiBTaG93IHlvdXIgc29sdXRpb24gZm9yIGVhY2guKSBUagowIC0xNiBUZAooKSBUagowIC'
      '0xNiBUZAooMS4gIFNvbHZlIGJ5IGZhY3RvcmluZzogIHheMiAtIDd4ICsgMTIgPSAwKSBUagowIC0xNiBUZAoo'
      'Mi4gIFNvbHZlIGJ5IGZhY3RvcmluZzogIDJ4XjIgKyA1eCAtIDMgPSAwKSBUagowIC0xNiBUZAooMy4gIENvbX'
      'BsZXRlIHRoZSBzcXVhcmU6ICB4XjIgKyA2eCAtIDE2ID0gMCkgVGoKMCAtMTYgVGQKKDQuICBVc2UgdGhlIHF1'
      'YWRyYXRpYyBmb3JtdWxhOiAgM3heMiAtIDJ4IC0gOCA9IDApIFRqCjAgLTE2IFRkCig1LiAgRmluZCB0aGUgZG'
      'lzY3JpbWluYW50IGFuZCBkZXNjcmliZSB0aGUgcm9vdHM6ICB4XjIgKyA0eCArIDUgPSAwKSBUagowIC0xNiBU'
      'ZAooNi4gIFRoZSBwcm9kdWN0IG9mIHR3byBjb25zZWN1dGl2ZSBpbnRlZ2VycyBpcyAxNTYuIEZpbmQgdGhlbS'
      '4pIFRqCjAgLTE2IFRkCig3LiAgQSByZWN0YW5nbGUgaXMgMyBjbSBsb25nZXIgdGhhbiBpdCBpcyB3aWRlIGFu'
      'ZCBoYXMgYW4gYXJlYSBvZikgVGoKMCAtMTYgVGQKKCAgICAgNzAgY21eMi4gRmluZCBpdHMgZGltZW5zaW9ucy'
      '4pIFRqCjAgLTE2IFRkCig4LiAgU2tldGNoIHkgPSB4XjIgLSA0eCArIDMsIGxhYmVsbGluZyB0aGUgdmVydGV4'
      'IGFuZCBpbnRlcmNlcHRzLikgVGoKMCAtMTYgVGQKKDkuICBGb3Igd2hhdCB2YWx1ZXMgb2YgayBkb2VzIHheMi'
      'ArIGt4ICsgOSA9IDAgaGF2ZSBvbmUgcm9vdD8pIFRqCjAgLTE2IFRkCigxMC4gV3JpdGUgYSBxdWFkcmF0aWMg'
      'd2hvc2Ugcm9vdHMgYXJlIC0yIGFuZCA1LikgVGoKMCAtMTYgVGQKKCkgVGoKMCAtMTYgVGQKKFN1Ym1pdCB0aH'
      'JvdWdoIHRoZSBwb3J0YWwsIG9yIGhhbmQgaW4gb24gcGFwZXIgTW9uZGF5LikgVGoKMCAtMTYgVGQKRVQKZW5k'
      'c3RyZWFtCmVuZG9iago1IDAgb2JqCjw8IC9UeXBlIC9Gb250IC9TdWJ0eXBlIC9UeXBlMSAvQmFzZUZvbnQgL0'
      'hlbHZldGljYSA+PgplbmRvYmoKeHJlZgowIDYKMDAwMDAwMDAwMCA2NTUzNSBmIAowMDAwMDAwMDA5IDAwMDAw'
      'IG4gCjAwMDAwMDAwNTggMDAwMDAgbiAKMDAwMDAwMDExNSAwMDAwMCBuIAowMDAwMDAwMjQxIDAwMDAwIG4gCj'
      'AwMDAwMDEyODMgMDAwMDAgbiAKdHJhaWxlcgo8PCAvU2l6ZSA2IC9Sb290IDEgMCBSID4+CnN0YXJ0eHJlZgox'
      'MzUzCiUlRU9GCg==';

  /// The online quiz. For online coursework the file *is* the work, which
  /// is why the detail screen gives it the emphasis it does.
  static const quiz3CellDivision =
      'data:application/pdf;base64,JVBERi0xLjQKMSAwIG9iago8PCAvVHlwZSAvQ2F0YWxvZyAvUGFnZXMgMi'
      'AwIFIgPj4KZW5kb2JqCjIgMCBvYmoKPDwgL1R5cGUgL1BhZ2VzIC9LaWRzIFszIDAgUl0gL0NvdW50IDEgPj4K'
      'ZW5kb2JqCjMgMCBvYmoKPDwgL1R5cGUgL1BhZ2UgL1BhcmVudCAyIDAgUiAvTWVkaWFCb3ggWzAgMCA2MTIgNz'
      'kyXSAvUmVzb3VyY2VzIDw8IC9Gb250IDw8IC9GMSA1IDAgUiA+PiA+PiAvQ29udGVudHMgNCAwIFIgPj4KZW5k'
      'b2JqCjQgMCBvYmoKPDwgL0xlbmd0aCA3NTAgPj4Kc3RyZWFtCkJUCi9GMSAxNiBUZgo2MCA3NjAgVGQKKFF1aX'
      'ogMyAtIENlbGwgRGl2aXNpb24pIFRqCi9GMSAxMSBUZgowIC0yOCBUZAooVHdlbnR5IG1pbnV0ZXMuIEFuc3dl'
      'ciBpbiB0aGUgcG9ydGFsLikgVGoKMCAtMTYgVGQKKCkgVGoKMCAtMTYgVGQKKDEuIE5hbWUgdGhlIGZvdXIgcG'
      'hhc2VzIG9mIG1pdG9zaXMgaW4gb3JkZXIuKSBUagowIC0xNiBUZAooMi4gSW4gd2hpY2ggcGhhc2UgZG8gY2hy'
      'b21vc29tZXMgbGluZSB1cCBhdCB0aGUgY2VsbCBlcXVhdG9yPykgVGoKMCAtMTYgVGQKKDMuIEhvdyBtYW55IG'
      'RhdWdodGVyIGNlbGxzIGRvZXMgbWl0b3NpcyBwcm9kdWNlLCBhbmQgYXJlIHRoZXkpIFRqCjAgLTE2IFRkCigg'
      'ICAgaWRlbnRpY2FsIHRvIHRoZSBwYXJlbnQgY2VsbD8pIFRqCjAgLTE2IFRkCig0LiBIb3cgbWFueSBkYXVnaH'
      'RlciBjZWxscyBkb2VzIG1laW9zaXMgcHJvZHVjZT8pIFRqCjAgLTE2IFRkCig1LiBHaXZlIG9uZSByZWFzb24g'
      'YSBib2R5IG5lZWRzIG1pdG9zaXMuKSBUagowIC0xNiBUZAooNi4gV2hhdCBpcyBjeXRva2luZXNpcz8pIFRqCj'
      'AgLTE2IFRkCig3LiBXaGF0IGhhcHBlbnMgZHVyaW5nIGludGVycGhhc2U/KSBUagowIC0xNiBUZAooOC4gV2hp'
      'Y2ggcHJvY2VzcyBwcm9kdWNlcyBnYW1ldGVzPykgVGoKMCAtMTYgVGQKKDkuIERlZmluZSBjaHJvbWF0aWQuKS'
      'BUagowIC0xNiBUZAooMTAuIFdoeSBkb2VzIG1laW9zaXMgaW5jcmVhc2UgZ2VuZXRpYyB2YXJpYXRpb24/KSBU'
      'agowIC0xNiBUZApFVAplbmRzdHJlYW0KZW5kb2JqCjUgMCBvYmoKPDwgL1R5cGUgL0ZvbnQgL1N1YnR5cGUgL1'
      'R5cGUxIC9CYXNlRm9udCAvSGVsdmV0aWNhID4+CmVuZG9iagp4cmVmCjAgNgowMDAwMDAwMDAwIDY1NTM1IGYg'
      'CjAwMDAwMDAwMDkgMDAwMDAgbiAKMDAwMDAwMDA1OCAwMDAwMCBuIAowMDAwMDAwMTE1IDAwMDAwIG4gCjAwMD'
      'AwMDAyNDEgMDAwMDAgbiAKMDAwMDAwMTA0MiAwMDAwMCBuIAp0cmFpbGVyCjw8IC9TaXplIDYgL1Jvb3QgMSAw'
      'IFIgPj4Kc3RhcnR4cmVmCjExMTIKJSVFT0YK';

  /// Reading material rather than something to hand in -- a lesson, so
  /// the detail screen shows no submission panel under it.
  static const floranteAtLaura =
      'data:application/pdf;base64,JVBERi0xLjQKMSAwIG9iago8PCAvVHlwZSAvQ2F0YWxvZyAvUGFnZXMgMi'
      'AwIFIgPj4KZW5kb2JqCjIgMCBvYmoKPDwgL1R5cGUgL1BhZ2VzIC9LaWRzIFszIDAgUl0gL0NvdW50IDEgPj4K'
      'ZW5kb2JqCjMgMCBvYmoKPDwgL1R5cGUgL1BhZ2UgL1BhcmVudCAyIDAgUiAvTWVkaWFCb3ggWzAgMCA2MTIgNz'
      'kyXSAvUmVzb3VyY2VzIDw8IC9Gb250IDw8IC9GMSA1IDAgUiA+PiA+PiAvQ29udGVudHMgNCAwIFIgPj4KZW5k'
      'b2JqCjQgMCBvYmoKPDwgL0xlbmd0aCA3NjIgPj4Kc3RyZWFtCkJUCi9GMSAxNiBUZgo2MCA3NjAgVGQKKEZsb3'
      'JhbnRlIGF0IExhdXJhIC0gQ2FudG8gMSB0byA1KSBUagovRjEgMTEgVGYKMCAtMjggVGQKKFJlYWRpbmcgYXNz'
      'aWdubWVudC4gQnJpbmcgeW91ciBub3RlcyB0byBUaHVyc2RheSdzIGRpc2N1c3Npb24uKSBUagowIC0xNiBUZA'
      'ooKSBUagowIC0xNiBUZAooRnJhbmNpc2NvIEJhbGFndGFzIGJlZ2lucyBpbiB0aGUgZm9yZXN0IG9mIEFsYmFu'
      'aWEsIHdoZXJlKSBUagowIC0xNiBUZAooRmxvcmFudGUgaXMgYm91bmQgdG8gYSB0cmVlIGFuZCBsZWZ0IHRvIG'
      'dyaWV2ZS4gUmVhZCBDYW50b3MgMSkgVGoKMCAtMTYgVGQKKHRocm91Z2ggNSBhbmQgdGFrZSBub3RlIG9mIHRo'
      'ZSBmb2xsb3dpbmcgYXMgeW91IGdvOikgVGoKMCAtMTYgVGQKKCkgVGoKMCAtMTYgVGQKKCAgLSBIb3cgQmFsYW'
      'd0YXMgdXNlcyB0aGUgZm9yZXN0IHRvIHNldCB0aGUgbW9vZCBvZiB0aGUgcG9lbS4pIFRqCjAgLTE2IFRkCigg'
      'IC0gVGhlIG9yZGVyIGluIHdoaWNoIHdlIGxlYXJuIGFib3V0IEZsb3JhbnRlJ3MgcGFzdC4pIFRqCjAgLTE2IF'
      'RkCiggIC0gV2hhdCB3ZSBhcmUgdG9sZCBhYm91dCBMYXVyYSBiZWZvcmUgc2hlIGV2ZXIgYXBwZWFycy4pIFRq'
      'CjAgLTE2IFRkCiggIC0gQW55IGxpbmUgeW91IGhhZCB0byByZWFkIHR3aWNlLiBCcmluZyBpdCB0byBjbGFzcy'
      '4pIFRqCjAgLTE2IFRkCigpIFRqCjAgLTE2IFRkCihUaGUgdGV4dCBpcyBpbiB5b3VyIHJlYWRlciwgcGFnZXMg'
      'MTIgdG8gMzQuKSBUagowIC0xNiBUZApFVAplbmRzdHJlYW0KZW5kb2JqCjUgMCBvYmoKPDwgL1R5cGUgL0Zvbn'
      'QgL1N1YnR5cGUgL1R5cGUxIC9CYXNlRm9udCAvSGVsdmV0aWNhID4+CmVuZG9iagp4cmVmCjAgNgowMDAwMDAw'
      'MDAwIDY1NTM1IGYgCjAwMDAwMDAwMDkgMDAwMDAgbiAKMDAwMDAwMDA1OCAwMDAwMCBuIAowMDAwMDAwMTE1ID'
      'AwMDAwIG4gCjAwMDAwMDAyNDEgMDAwMDAgbiAKMDAwMDAwMTA1NCAwMDAwMCBuIAp0cmFpbGVyCjw8IC9TaXpl'
      'IDYgL1Jvb3QgMSAwIFIgPj4Kc3RhcnR4cmVmCjExMjQKJSVFT0YK';
}
