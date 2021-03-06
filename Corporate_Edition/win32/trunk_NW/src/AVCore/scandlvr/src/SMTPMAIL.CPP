// PROPRIETARY/CONFIDENTIAL. Use of this product is subject to license terms.
// Copyright 1996, 2005 Symantec, Peter Norton Product Group. All rights reserved.
//************************************************************************
//
// $Header:   S:/SOCKLIB/VCS/SMTPMAIL.CPv   1.0   25 Apr 1997 11:51:46   ksackin  $
//
// Description:
//  Source file for SMTP mail module.
//
// Contains:
//      SMTPSocketReadReplyCode()
//      SMTPSocketReadLine()
//      SMTPSocketWriteLine()
//      SMTPSocketWriteBuffer()
//      SMTPInitiateMailConnection()
//      SMTPConnectionAddRecipient()
//      SMTPConnectionStartData()
//      SMTPConnectionSendData()
//      SMTPFinishMailConnection()
//      SMTPSendMailStart()
//      SMTPSendMailStartEx()
//      SMTPSendMail()
//
// See Also:
//
//************************************************************************
// $Log:   S:/SOCKLIB/VCS/SMTPMAIL.CPv  $
// 
//    Rev 1.0   25 Apr 1997 11:51:46   ksackin
// Initial revision.
// 
//    Rev 1.7   16 Apr 1997 02:40:16   DJesch
// Added <angle brackets> around the recipient name so that Seattle Labs'
// SMTP mail server can receive messages from us.
//
//    Rev 1.6   16 Dec 1996 13:07:32   RAY
// Now expecting a response after terminating "\r\n.\r\n".
//
//    Rev 1.5   13 Dec 1996 17:24:34   RAY
// Added SMTPSendMailStartEx() which is just like SMTPSendMailStart() except
// it takes lpszAddlHdrs for sophisticated messaging capabilities. :)
//
//    Rev 1.4   13 Dec 1996 17:06:54   DJesch
// Added some more debugging output.
//
//    Rev 1.3   06 Dec 1996 20:51:52   DCHI
// Corrected problem when reading multi-line responses.
//
//    Rev 1.2   26 Nov 1996 15:29:24   DJesch
// No real changes.
//
//    Rev 1.1   04 Nov 1996 14:02:56   CNACHEN
// Added error checking in greeting code
//
//    Rev 1.0   24 Sep 1996 17:34:04   DJesch
// Initial revision.
//
//************************************************************************

#include "stdafx.h"
#include <stdio.h>
#include <string.h>
#include "SymSaferStrings.h"

#include "avtypes.h"

#include "smtpmail.h"

#define SMTP_REPLY_CODE_OK                  250
#define SMTP_REPLY_CODE_WILL_FORWARD        251
#define SMTP_REPLY_CODE_START_MAIL_INPUT    354
#define SMTP_REPLY_CODE_GREETING            220

//*************************************************************************
//
// SMTP_STATUS SMTPSocketReadReplyCode()
//
// Parameters:
//  hSocket                 The socket from which to read the response
//  lpnReplyCode            Pointer to integer to store reply code
//
// Description:
//  The function expects every line to begin with the same three
//  digit reply code and that all lines except the last will have
//  a hyphen following the reply code.  The last line is expected
//  to have a space following the reply code.
//
//  The function expects the first line to begin with a three digit
//  number which is read and translated into an integer and stored
//  at *lpnReplyCode.
//
// Returns:
//  SMTP_STATUS_OK      On success
//  SMTP_STATUS_ERROR   On error
//
//*************************************************************************

SMTP_STATUS SMTPSocketReadReplyCode
(
    HSOCKET     hSocket,
    LPINT       lpnReplyCode
)
{
    char        ch;             // Buffer for read of char at a time
    int         i;              // Current buffer index
    int         nBytesReceived;
    DWORD       dwError;
    BOOL        bLastLine;

    *lpnReplyCode = 0;
    i = 0;
    bLastLine = FALSE;
    while (1)
    {
        // Read one character

        if (SocketReceive(hSocket,&ch,1,&nBytesReceived,&dwError) ==
            SOCKET_STATUS_OK)
        {
            if (nBytesReceived == 1)
            {
                if (i == 3 && ch == ' ')
                {
                    // Assumption is that the last line of the
                    //  reply will always have a space before
                    //  the CRLF

                    bLastLine = TRUE;
                    ++i;
                }
                else
                if (ch == '\n')
                {
                    if (bLastLine == TRUE || i < 4)
                    {
                        // Saw a newline and (it was the last line
                        //  or not enough characters seen)

                        if (i < 4)
                        {
                            return(SMTP_STATUS_ERROR);
                        }

                        return(SMTP_STATUS_OK);
                    }

                    // New line

                    i = 0;
                    *lpnReplyCode = 0;
                }
                else
                if (i < 3)
                {
                    // Is it a numeric digit

                    if (ch < '0' || ch > '9')
                    {
                        return(SMTP_STATUS_ERROR);
                    }

                    // It was a numeric digit as expected

                    *lpnReplyCode = *lpnReplyCode * 10 + (ch - '0');
                    ++i;
                }
                else
                    ++i;
            }
            else
            {
                // Socket was closed or other error

                return(SMTP_STATUS_ERROR);
            }
        }
        else
		{
            // An error occurred, just return with what we have

            return(SMTP_STATUS_ERROR);
		}
    }
}


//*************************************************************************
//
// SMTP_STATUS SMTPReadLine()
//
// Parameters:
//  hSocket                 The socket from which to read a line
//  lpszBuf                 A buffer to store the line, or NULL if the
//                          function should throw away the input
//  nBufLen                 The length of the buffer
//
// Description:
//  Reads a line from the socket.  The line is terminated by a newline
//  character ('\n').  If a carriage return ('\r') precedes the newline
//  it is not returned.
//
//  If lpszBuf is NULL, the functionality is the same except that the
//  input is not saved.
//
// Returns:
//  SMTP_STATUS_OK      On success
//  SMTP_STATUS_ERROR   On error
//
//*************************************************************************

SMTP_STATUS SMTPSocketReadLine
(
    HSOCKET     hSocket,
    LPSTR       lpszBuf,
    int         nBufLen
)
{
    BYTE        byPrev;         // Previous read byte
    BYTE        by;             // Buffer for read of BYTE at a time
    int         i;              // Current buffer index
    int         nBytesReceived; // Return value from recv()
    DWORD       dwError;

    byPrev = 0;
    i = 0;
    while (1)
    {
        // First check to see if the buffer length was exceeded

        if (lpszBuf != NULL && i >= nBufLen-1)
		{
            // Buffer length exceeded, just return what we have

            if (lpszBuf != NULL)
                lpszBuf[nBufLen-1] = 0;

            return(SMTP_STATUS_OK);
		}

        // Read one character

        if (SocketReceive(hSocket,&by,1,&nBytesReceived,&dwError) ==
            SOCKET_STATUS_OK)
        {
            if (nBytesReceived == 1)
            {
                if (by == '\n')
                {
                    // Saw a newline, so return

                    if (lpszBuf != NULL)
                    {
                        if (i > 0 && byPrev == '\r')
                        {
                            // Get rid of the carriage return character

                            lpszBuf[--i] = 0;
                        }
                        else
                            lpszBuf[i] = 0;
                    }

                    return(SMTP_STATUS_OK);
                }
                else
                if (lpszBuf != NULL)
                    lpszBuf[i] = by;

                byPrev = by;
                ++i;
            }
            else
            {
                // Socket was closed or other error, just return
                //  with what we have

                if (lpszBuf != NULL)
                    lpszBuf[i] = 0;

                return(SMTP_STATUS_ERROR);
            }
        }
        else
		{
            // An error occurred, just return with what we have

            if (lpszBuf != NULL)
                lpszBuf[i] = 0;

            return(SMTP_STATUS_ERROR);
		}
    }
}


//*************************************************************************
//
// SMTP_STATUS SMTPWriteLine()
//
// Parameters:
//  hSocket                 The socket from which to read a line
//  lpszBuf                 The buffer containing the line to write
//
// Description:
//  Writes the contents of lpszBuf to the socket, followed by a
//  carriage return and linefeed.
//
// Returns:
//  SMTP_STATUS_OK      On success
//  SMTP_STATUS_ERROR   On error
//
//*************************************************************************

SMTP_STATUS SMTPSocketWriteLine
(
    HSOCKET     hSocket,
    LPSTR       lpszBuf
)
{
    int         nBytesToSend;
    int         nBytesSent;
    DWORD       dwError;

    // Send the buffer

    nBytesToSend = strlen(lpszBuf);
    if (SocketSend(hSocket,
                   lpszBuf,
                   nBytesToSend,
                   &nBytesSent,
                   &dwError) != SOCKET_STATUS_OK ||
        nBytesSent != nBytesToSend)
    {
        return(SMTP_STATUS_ERROR);
    }

    // Send the carriage return and line feed

    nBytesToSend = 2;
    if (SocketSend(hSocket,
                   "\r\n",
                   nBytesToSend,
                   &nBytesSent,
                   &dwError) != SOCKET_STATUS_OK ||
        nBytesSent != nBytesToSend)
    {
        return(SMTP_STATUS_ERROR);
    }

    return(SMTP_STATUS_OK);
}


//*************************************************************************
//
// SMTP_STATUS SMTPWriteBuffer()
//
// Parameters:
//  hSocket                 The socket from which to read a line
//  lpbyBuf                 The buffer to write
//  nBytesToWrite           The number of bytes to write
//  lpnBytesWritten         For storing number of bytes written
//                          on success
//
// Description:
//  Writes the contents of the buffer to the socket.
//
// Returns:
//  SMTP_STATUS_OK      On success
//  SMTP_STATUS_ERROR   On error
//
//*************************************************************************

SMTP_STATUS SMTPSocketWriteBuffer
(
    HSOCKET     hSocket,
    LPBYTE      lpbyBuf,
    int         nBytesToWrite,
    LPINT       lpnBytesWritten
)
{
    DWORD       dwError;

    if (SocketSend(hSocket,
                   lpbyBuf,
                   nBytesToWrite,
                   lpnBytesWritten,
                   &dwError) != SOCKET_STATUS_OK)
    {
        // Error during send

        return(SMTP_STATUS_ERROR);
    }

    return(SMTP_STATUS_OK);
}


//*************************************************************************
//
// SMTP_STATUS SMTPInitiateMailConnection()
//
// Parameters:
//  lpstSMTPConnection      Pointer to SMTP_CONNECTION_T structure
//                          to hold connection information
//  lpstSMTPServerAddress   Pointer to SOCKET_ADDRESS_T
//                          structure holding server address info
//  lpszSender              The address of the sender
//
// Description:
//  Creates an SMTP connection with the given server and initializes
//  the connection by specifying the sender of the mail.
//
// Returns:
//  SMTP_STATUS_OK      On success
//  SMTP_STATUS_ERROR   On failure
//
//*************************************************************************

SMTP_STATUS SMTPInitiateMailConnection
(
    LPSMTP_CONNECTION       lpstSMTPConnection,
    LPSOCKET_ADDRESS        lpstSMTPServerAddress,
    LPSTR                   lpszSender
)
{
    int                     nBytesWritten;
    int                     nReplyCode;
    DWORD                   dwError;

    // Initialize flags

    lpstSMTPConnection->dwFlags = 0;

    //////////////////////////////////////////////////////////////////
    // Connect to the SMTP server
    //////////////////////////////////////////////////////////////////

    // Create a socket for connecting to the SMTP server

    if (SocketCreate(&lpstSMTPConnection->hSocket,
                     FALSE, // blocking,
                     FALSE, // don't linger
                     0,     // timeout = 0
                     &dwError) !=
        SOCKET_STATUS_OK)
    {
        // Failed to create a socket

        lpstSMTPConnection->dwError = SMTP_ERROR_SOCKET_CREATION;

        return(SMTP_STATUS_ERROR);
    }

    // Connect to the SMTP server

    if (SocketConnect(lpstSMTPConnection->hSocket,
                      lpstSMTPServerAddress,
                      &dwError) != SOCKET_STATUS_OK)
    {
        lpstSMTPConnection->dwError = SMTP_ERROR_SERVER_CONNECTION;

        SocketDestroy(lpstSMTPConnection->hSocket,&dwError);

        return(SMTP_STATUS_ERROR);
    }

    //////////////////////////////////////////////////////////////////
    // Skip the greeting
    //////////////////////////////////////////////////////////////////

    if (SMTPSocketReadReplyCode(lpstSMTPConnection->hSocket,
                                &nReplyCode) == SMTP_STATUS_ERROR ||
        nReplyCode != SMTP_REPLY_CODE_GREETING)
    {
        lpstSMTPConnection->dwError = SMTP_ERROR_BAD_GREETING;

        SocketDestroy(lpstSMTPConnection->hSocket,&dwError);

        return(SMTP_STATUS_ERROR);
    }

    //////////////////////////////////////////////////////////////////
    // Send HELO greeting
    //////////////////////////////////////////////////////////////////

    if (SMTPSocketWriteLine(lpstSMTPConnection->hSocket,
                            "HELO SMTP") == SMTP_STATUS_ERROR)
    {
        // No greeting?

        lpstSMTPConnection->dwError = SMTP_ERROR_GREETING_SEND;

        SocketDestroy(lpstSMTPConnection->hSocket,&dwError);

        return(SMTP_STATUS_ERROR);
    }

    // Don't care about the response to HELO

    if (SMTPSocketReadReplyCode(lpstSMTPConnection->hSocket,
                                &nReplyCode) == SMTP_STATUS_ERROR ||
        nReplyCode != SMTP_REPLY_CODE_OK)
    {
        lpstSMTPConnection->dwError = SMTP_ERROR_GREETING_REPLY;

        SocketDestroy(lpstSMTPConnection->hSocket,&dwError);

        return(SMTP_STATUS_ERROR);
    }

    //////////////////////////////////////////////////////////////////
    // MAIL FROM:
    //////////////////////////////////////////////////////////////////

    // Send MAIL FROM:lpszSender\r\n

    if (SMTPSocketWriteBuffer(lpstSMTPConnection->hSocket,
                              (LPBYTE)"MAIL FROM:",
                              10,
                              &nBytesWritten) == SMTP_STATUS_ERROR ||
        nBytesWritten != 10 ||
        SMTPSocketWriteLine(lpstSMTPConnection->hSocket,
                            lpszSender) == SMTP_STATUS_ERROR)
    {
        // Failed to send MAIL FROM:

        lpstSMTPConnection->dwError = SMTP_ERROR_MAILFROM_SEND;

        SocketDestroy(lpstSMTPConnection->hSocket,&dwError);

        return(SMTP_STATUS_ERROR);
    }

    //////////////////////////////////////////////////////////////////
    // Check the response
    //////////////////////////////////////////////////////////////////

    if (SMTPSocketReadReplyCode(lpstSMTPConnection->hSocket,
                                &nReplyCode) == SMTP_STATUS_ERROR ||
        nReplyCode != SMTP_REPLY_CODE_OK)
    {
        lpstSMTPConnection->dwError = SMTP_ERROR_MAILFROM_REPLY;

        SocketDestroy(lpstSMTPConnection->hSocket,&dwError);

        return(SMTP_STATUS_ERROR);
    }

    lpstSMTPConnection->dwFlags |= SMTP_CONNECTION_FLAG_SENDER_SPECIFIED;

    return(SMTP_STATUS_OK);
}


//*************************************************************************
//
// SMTP_STATUS SMTPConnectionAddRecipient()
//
// Parameters:
//  lpstSMTPConnection      Pointer to SMTP_CONNECTION_T structure
//                          to holding connection information
//  lpszRecipient           The address of the recipient
//
// Description:
//  Adds a recipient to a mail send connection.
//
// Returns:
//  SMTP_STATUS_OK      On success
//  SMTP_STATUS_ERROR   On failure
//
//*************************************************************************

SMTP_STATUS SMTPConnectionAddRecipient
(
    LPSMTP_CONNECTION       lpstSMTPConnection,
    LPSTR                   lpszRecipient
)
{
    char                    szBuffer[1025];
//  int                     nBytesWritten;
    int                     nReplyCode;

    // Make sure connection was initialized successfully

    if ((lpstSMTPConnection->dwFlags &
            SMTP_CONNECTION_FLAG_SENDER_SPECIFIED) == 0)
    {
        lpstSMTPConnection->dwError = SMTP_ERROR_RECIPIENT_BEFORE_SENDER;

        // Was not initialized successfully

        return(SMTP_STATUS_ERROR);
    }

    //////////////////////////////////////////////////////////////////
    // RCPT TO:lpszRecipient\r\n
    //////////////////////////////////////////////////////////////////

    sssnprintf(szBuffer,
            sizeof(szBuffer),
            "RCPT TO:<%s>",
            lpszRecipient);

    if (SMTPSocketWriteLine(lpstSMTPConnection->hSocket,
                            szBuffer) == SMTP_STATUS_ERROR)
    {
        lpstSMTPConnection->dwError = SMTP_ERROR_RCPTTO_SEND;

        // Failed to send RCPT TO:

        return (SMTP_STATUS_ERROR);
    }

#if 0
    if (SMTPSocketWriteBuffer(lpstSMTPConnection->hSocket,
                              (LPBYTE)"RCPT TO:",
                              8,
                              &nBytesWritten) == SMTP_STATUS_ERROR ||
        nBytesWritten != 8 ||
        SMTPSocketWriteLine(lpstSMTPConnection->hSocket,
                            lpszRecipient) == SMTP_STATUS_ERROR)
    {
        lpstSMTPConnection->dwError = SMTP_ERROR_RCPTTO_SEND;

        // Failed to send RCPT TO:

        return(SMTP_STATUS_ERROR);
    }
#endif

    //////////////////////////////////////////////////////////////////
    // Check the response
    //////////////////////////////////////////////////////////////////

    if (SMTPSocketReadReplyCode(lpstSMTPConnection->hSocket,
                                &nReplyCode) == SMTP_STATUS_ERROR ||
        nReplyCode != SMTP_REPLY_CODE_OK &&
        nReplyCode != SMTP_REPLY_CODE_WILL_FORWARD)
    {
        lpstSMTPConnection->dwError = SMTP_ERROR_RCPTTO_REPLY;

        return(SMTP_STATUS_ERROR);
    }

    lpstSMTPConnection->dwFlags |= SMTP_CONNECTION_FLAG_RECIPIENT_SPECIFIED;

    return(SMTP_STATUS_OK);
}


//*************************************************************************
//
// SMTP_STATUS SMTPConnectionStartData()
//
// Parameters:
//  lpstSMTPConnection      Pointer to SMTP_CONNECTION_T structure
//                          holding connection information
//
// Description:
//  Primes the connection for the data part of the message.
//
// Returns:
//  SMTP_STATUS_OK      On success
//  SMTP_STATUS_ERROR   On failure
//
//*************************************************************************

SMTP_STATUS SMTPConnectionStartData
(
    LPSMTP_CONNECTION       lpstSMTPConnection
)
{
    int                     nReplyCode;

    // Make sure both sender and recipient have already been specified

    if ((lpstSMTPConnection->dwFlags &
            (SMTP_CONNECTION_FLAG_SENDER_SPECIFIED |
             SMTP_CONNECTION_FLAG_RECIPIENT_SPECIFIED)) !=
            (SMTP_CONNECTION_FLAG_SENDER_SPECIFIED |
             SMTP_CONNECTION_FLAG_RECIPIENT_SPECIFIED))
    {
        // One or both have not been specified

        lpstSMTPConnection->dwError =
            SMTP_ERROR_DATA_BEFORE_SENDER_OR_RECIPIENT;

        return(SMTP_STATUS_ERROR);
    }

    //////////////////////////////////////////////////////////////////
    // DATA
    //////////////////////////////////////////////////////////////////

    if (SMTPSocketWriteLine(lpstSMTPConnection->hSocket,
                            "DATA") == SMTP_STATUS_ERROR)
    {
        // Failed to send DATA

        lpstSMTPConnection->dwError = SMTP_ERROR_DATA_SEND;

        return(SMTP_STATUS_ERROR);
    }

    //////////////////////////////////////////////////////////////////
    // Check the response
    //////////////////////////////////////////////////////////////////

    if (SMTPSocketReadReplyCode(lpstSMTPConnection->hSocket,
                                &nReplyCode) == SMTP_STATUS_ERROR ||
        nReplyCode != SMTP_REPLY_CODE_START_MAIL_INPUT)
    {
        lpstSMTPConnection->dwError = SMTP_ERROR_DATA_REPLY;

        return(SMTP_STATUS_ERROR);
    }

    lpstSMTPConnection->dwFlags |= SMTP_CONNECTION_FLAG_DATA_SPECIFIED |
        SMTP_CONNECTION_FLAG_AT_BEGINNING_OF_LINE;
    return(SMTP_STATUS_OK);
}


//*************************************************************************
//
// SMTP_STATUS SMTPConnectionSendData()
//
// Parameters:
//  lpstSMTPConnection      Pointer to SMTP_CONNECTION_T structure
//                          holding connection information
//  lpszBuf                 A zero-terminated buffer containing
//                          data to send.
//
// Description:
//  Appends the data at lpszBuf to the data to send.  The data at
//  lpszBuf should be zero-terminated.  SMTPConnectionStartData()
//  must have been called before the first call to this function.
//
//  This function correctly inserts leading '.'s where necessary.
//
// Returns:
//  SMTP_STATUS_OK      On success
//  SMTP_STATUS_ERROR   On failure
//
//*************************************************************************

SMTP_STATUS SMTPConnectionSendData
(
    LPSMTP_CONNECTION       lpstSMTPConnection,
    LPSTR                   lpszBuf
)
{
    LPSTR                   lpszEnd;
    int                     nBytesToWrite;
    int                     nBytesWritten;

    // Make sure SMTPConnectionStartData() was successfully called

    if ((lpstSMTPConnection->dwFlags &
            SMTP_CONNECTION_FLAG_DATA_SPECIFIED) == 0)
    {
        // SMTPConnectionStartData() had not been called successfully

        lpstSMTPConnection->dwError = SMTP_ERROR_DATA_BEFORE_DATA_START;

        return(SMTP_STATUS_ERROR);
    }

    lpszEnd = lpszBuf;
    while (*lpszBuf)
    {
        // Search for the end of a newline followed by a '.'

        while (*lpszEnd)
        {
            if (*lpszEnd++ == '\n' && *lpszEnd == '.')
                break;
        }

        if (*lpszBuf == '.' &&
            (lpstSMTPConnection->dwFlags &
                SMTP_CONNECTION_FLAG_AT_BEGINNING_OF_LINE))
        {
            // Output an extra period

            if (SMTPSocketWriteBuffer(lpstSMTPConnection->hSocket,
                                      (LPBYTE)".",
                                      1,
                                      &nBytesWritten) != SMTP_STATUS_OK)
            {
                // Failed to write leading period

                lpstSMTPConnection->dwError = SMTP_ERROR_SENDING_DATA;

                return(SMTP_STATUS_ERROR);
            }
        }

        // Write the data passed in

        nBytesToWrite = lpszEnd - lpszBuf;

        if (SMTPSocketWriteBuffer(lpstSMTPConnection->hSocket,
                                  (LPBYTE)lpszBuf,
                                  nBytesToWrite,
                                  &nBytesWritten) != SMTP_STATUS_OK ||
            nBytesWritten != nBytesToWrite)
        {
            // Failed to write bytes

            lpstSMTPConnection->dwError = SMTP_ERROR_SENDING_DATA;

            return(SMTP_STATUS_ERROR);
        }

        if (lpszEnd[-1] == '\n')
        {
            // Back at the beginning of a line

            lpstSMTPConnection->dwFlags |=
                SMTP_CONNECTION_FLAG_AT_BEGINNING_OF_LINE;
        }
        else
        {
            // Not at the beginning of a line

            lpstSMTPConnection->dwFlags &=
                ~(SMTP_CONNECTION_FLAG_AT_BEGINNING_OF_LINE);
        }

        lpszBuf = lpszEnd;
    }

    return(SMTP_STATUS_OK);
}


//*************************************************************************
//
// SMTP_STATUS SMTPFinishMailConnection()
//
// Parameters:
//  lpstSMTPConnection      Pointer to SMTP_CONNECTION_T structure
//                          holding connection information
//
// Description:
//  Completes a mail connection.  This should never be called if
//  SMTPInitiateMailConnection() fails.
//
//  This assumes that a <CRLF>.<CRLF> followed by a QUIT
//  will end the transfer.
//
//  The function closes the associated socket regardless of the case.
//
// Returns:
//  SMTP_STATUS_OK      On success
//  SMTP_STATUS_ERROR   On failure
//
//*************************************************************************

SMTP_STATUS SMTPFinishMailConnection
(
    LPSMTP_CONNECTION       lpstSMTPConnection
)
{
    SMTP_STATUS             smtpStatus;
    int                     nBytesWritten;
    int                     nReplyCode;
    DWORD                   dwError;

    smtpStatus = SMTP_STATUS_OK;

    // Was data specified?

    if ((lpstSMTPConnection->dwFlags &
            (SMTP_CONNECTION_FLAG_SENDER_SPECIFIED |
             SMTP_CONNECTION_FLAG_RECIPIENT_SPECIFIED |
             SMTP_CONNECTION_FLAG_DATA_SPECIFIED)) !=
        (SMTP_CONNECTION_FLAG_SENDER_SPECIFIED |
         SMTP_CONNECTION_FLAG_RECIPIENT_SPECIFIED |
         SMTP_CONNECTION_FLAG_DATA_SPECIFIED))
    {
        // All steps were not taken

        lpstSMTPConnection->dwError =
            SMTP_ERROR_INCOMPLETE_MSG_BEFORE_FINISH;

        smtpStatus = SMTP_STATUS_ERROR;
    }
    else
    if (SMTPSocketWriteBuffer(lpstSMTPConnection->hSocket,
                              (LPBYTE)"\r\n.\r\n",
                              5,
                              &nBytesWritten) != SMTP_STATUS_OK ||
        nBytesWritten != 5 ||
        SMTP_STATUS_OK != SMTPSocketReadReplyCode( lpstSMTPConnection->hSocket,
                                                   &nReplyCode ) ||
        nReplyCode > 299 )
    {
        // Failed to write the <CRLF>.<CRLF>

        lpstSMTPConnection->dwError = SMTP_ERROR_END_OF_DATA_SEND;

        smtpStatus = SMTP_STATUS_ERROR;
    }

    // Send QUIT.  Don't care about the response nor whether
    //  an error occurred in sending it.

    SMTPSocketWriteLine(lpstSMTPConnection->hSocket,"QUIT");

    SMTPSocketReadReplyCode(lpstSMTPConnection->hSocket,&nReplyCode);

    if (SocketDestroy(lpstSMTPConnection->hSocket,
                      &dwError) != SOCKET_STATUS_OK)
    {
        lpstSMTPConnection->dwError = SMTP_ERROR_CLOSE_SOCKET;

        smtpStatus = SMTP_STATUS_ERROR;
    }

    return(smtpStatus);
}


//*************************************************************************
//
// SMTP_STATUS SMTPSendMailStart()
//
// Parameters:
//  lpstSMTPConnection      Pointer to SMTP_CONNECTION_T structure
//                          to hold connection information
//  lpstSMTPServerAddress   Pointer to SOCKET_ADDRESS_T
//                          structure holding server address info
//  lpszSender              The address of the sender
//  lpstRecipientList       The list recipients
//  lpszSubject             The subject
//
// Description:
//  Starts SMTP mail connection by sender headers.
//
//  This function is used for sending a series of data parts
//  separately using SMTPConnectionSendData().  The connection
//  should be completed by calling SMTPFinishMailConnection().
//
// Returns:
//  SMTP_STATUS_OK      On success
//  SMTP_STATUS_ERROR   On failure
//
//*************************************************************************

SMTP_STATUS SMTPSendMailStart
(
    LPSMTP_CONNECTION       lpstSMTPConnection,
    LPSOCKET_ADDRESS        lpstSMTPServerAddress,
    LPSTR                   lpszSender,
    LPINTERNET_EMAIL_LIST   lpstRecipientList,
    LPSTR                   lpszSubject
)
{
    return SMTPSendMailStartEx( lpstSMTPConnection,
                                lpstSMTPServerAddress,
                                lpszSender,
                                lpstRecipientList,
                                lpszSubject,
                                NULL );
}


//*************************************************************************
//
// SMTP_STATUS SMTPSendMailStartEx()
//
// Parameters:
//  lpstSMTPConnection      Pointer to SMTP_CONNECTION_T structure
//                          to hold connection information
//  lpstSMTPServerAddress   Pointer to SOCKET_ADDRESS_T
//                          structure holding server address info
//  lpszSender              The address of the sender
//  lpstRecipientList       The list recipients
//  lpszSubject             The subject
//  lpszAddlHdrs            Additional Headers
//
// Description:
//  Starts SMTP mail connection by sender headers.
//
//  This function is used for sending a series of data parts
//  separately using SMTPConnectionSendData().  The connection
//  should be completed by calling SMTPFinishMailConnection().
//
// Returns:
//  SMTP_STATUS_OK      On success
//  SMTP_STATUS_ERROR   On failure
//
//*************************************************************************

SMTP_STATUS SMTPSendMailStartEx
(
    LPSMTP_CONNECTION       lpstSMTPConnection,
    LPSOCKET_ADDRESS        lpstSMTPServerAddress,
    LPSTR                   lpszSender,
    LPINTERNET_EMAIL_LIST   lpstRecipientList,
    LPSTR                   lpszSubject,
    LPSTR                   lpszAddlHdrs
)
{
    LPINTERNET_EMAIL_LIST   lpstRecipient;

    if (SMTPInitiateMailConnection(lpstSMTPConnection,
                                   lpstSMTPServerAddress,
                                   lpszSender) != SMTP_STATUS_OK)
    {
lpstSMTPConnection->dwError = 1;
        // Failed to initiate mail connection

        return(SMTP_STATUS_ERROR);
    }

    // Add recipients

    lpstRecipient = lpstRecipientList;
    while (lpstRecipient != NULL)
    {
        if (SMTPConnectionAddRecipient(lpstSMTPConnection,
                                       lpstRecipient->szAddress) !=
            SMTP_STATUS_OK)
        {
lpstSMTPConnection->dwError = 2;
            // Failed to add recipient

            SMTPFinishMailConnection(lpstSMTPConnection);
            return(SMTP_STATUS_ERROR);
        }

        lpstRecipient = lpstRecipient->lpNext;
    }

    if (SMTPConnectionStartData(lpstSMTPConnection) != SMTP_STATUS_OK)
    {
lpstSMTPConnection->dwError = 3;
        // Failed to start DATA

        SMTPFinishMailConnection(lpstSMTPConnection);
        return(SMTP_STATUS_ERROR);
    }

    //////////////////////////////////////////////////////////////////
    // Add From:, Subject:, and To: fields
    //////////////////////////////////////////////////////////////////

    // From:

    if (SMTPConnectionSendData(lpstSMTPConnection,
                               "From: ") != SMTP_STATUS_OK)
    {
lpstSMTPConnection->dwError = 4;
        // Failed to send message

        SMTPFinishMailConnection(lpstSMTPConnection);
        return(SMTP_STATUS_ERROR);
    }

    if (SMTPConnectionSendData(lpstSMTPConnection,
                               lpszSender) != SMTP_STATUS_OK)
    {
lpstSMTPConnection->dwError = 5;
        // Failed to send message

        SMTPFinishMailConnection(lpstSMTPConnection);
        return(SMTP_STATUS_ERROR);
    }

    // Subject:

    if (SMTPConnectionSendData(lpstSMTPConnection,
                               "\r\nSubject: ") != SMTP_STATUS_OK)
    {
lpstSMTPConnection->dwError = 6;
        // Failed to send message

        SMTPFinishMailConnection(lpstSMTPConnection);
        return(SMTP_STATUS_ERROR);
    }

    if (SMTPConnectionSendData(lpstSMTPConnection,
                               lpszSubject) != SMTP_STATUS_OK)
    {
lpstSMTPConnection->dwError = 7;
        // Failed to send message

        SMTPFinishMailConnection(lpstSMTPConnection);
        return(SMTP_STATUS_ERROR);
    }

    // To:

    if (SMTPConnectionSendData(lpstSMTPConnection,
                               "\r\nTo: ") != SMTP_STATUS_OK)
    {
lpstSMTPConnection->dwError = 8;
        // Failed to send message

        SMTPFinishMailConnection(lpstSMTPConnection);
        return(SMTP_STATUS_ERROR);
    }

    lpstRecipient = lpstRecipientList;
    while (lpstRecipient != NULL)
    {
        if (SMTPConnectionSendData(lpstSMTPConnection,
                                   lpstRecipient->szAddress) !=
            SMTP_STATUS_OK)
        {
lpstSMTPConnection->dwError = 9;
            // Failed to send message

            SMTPFinishMailConnection(lpstSMTPConnection);
            return(SMTP_STATUS_ERROR);
        }

        lpstRecipient = lpstRecipient->lpNext;

        if (lpstRecipient != NULL)
        {
            // Add comma, newline, whitespace

            if (SMTPConnectionSendData(lpstSMTPConnection,
                                       ",\r\n    ") != SMTP_STATUS_OK)
            {
lpstSMTPConnection->dwError = 10;
                // Failed to send message

                SMTPFinishMailConnection(lpstSMTPConnection);
                return(SMTP_STATUS_ERROR);
            }
        }
    }

    if (SMTPConnectionSendData(lpstSMTPConnection,
                               "\r\n") != SMTP_STATUS_OK)
    {
lpstSMTPConnection->dwError = 11;
        // Failed to send message

        SMTPFinishMailConnection(lpstSMTPConnection);
        return(SMTP_STATUS_ERROR);
    }

    // This is for additional RFC822 headers in the form:
    //
    //      "Content-type: image/gif\r\nContent-encoding: text/plain\r\n"
    //
    if (lpszAddlHdrs != NULL &&
        SMTPConnectionSendData(lpstSMTPConnection,
                               lpszAddlHdrs) != SMTP_STATUS_OK)
    {
lpstSMTPConnection->dwError = 12;
        // Failed to send message

        SMTPFinishMailConnection(lpstSMTPConnection);
        return(SMTP_STATUS_ERROR);
    }


    // Blank line
    if (SMTPConnectionSendData(lpstSMTPConnection,
                               "\r\n") != SMTP_STATUS_OK)
    {
lpstSMTPConnection->dwError = 13;
        // Failed to send message

        SMTPFinishMailConnection(lpstSMTPConnection);
        return(SMTP_STATUS_ERROR);
    }

    return(SMTP_STATUS_OK);
}


//*************************************************************************
//
// SMTP_STATUS SMTPSendMail()
//
// Parameters:
//  lpstSMTPServerAddress   Pointer to SOCKET_ADDRESS_T
//                          structure holding server address info
//  lpszSender              The address of the sender
//  lpstRecipientList       The list recipients
//  lpszSubject             The subject
//  lpszMessage             The message to send
//  lpdwError               Pointer to DWORD to store error code on error
//
// Description:
//  Sends SMTP mail.
//
// Returns:
//  SMTP_STATUS_OK      On success
//  SMTP_STATUS_ERROR   On failure
//
//*************************************************************************

SMTP_STATUS SMTPSendMail
(
    LPSOCKET_ADDRESS        lpstSMTPServerAddress,
    LPSTR                   lpszSender,
    LPINTERNET_EMAIL_LIST   lpstRecipientList,
    LPSTR                   lpszSubject,
    LPSTR                   lpszMessage,
    LPDWORD                 lpdwError
)
{
    SMTP_CONNECTION_T       stSMTPConnection;

    if (SMTPSendMailStart(&stSMTPConnection,
                          lpstSMTPServerAddress,
                          lpszSender,
                          lpstRecipientList,
                          lpszSubject) != SMTP_STATUS_OK)
    {
        // Failed to initiate mail connection with headers

        *lpdwError = stSMTPConnection.dwError;
        return(SMTP_STATUS_ERROR);
    }

    // Send message body

    if (SMTPConnectionSendData(&stSMTPConnection,
                               lpszMessage) != SMTP_STATUS_OK)
    {
        // Failed to send message

        *lpdwError = stSMTPConnection.dwError;
        SMTPFinishMailConnection(&stSMTPConnection);

        return(SMTP_STATUS_ERROR);
    }

    if (SMTPFinishMailConnection(&stSMTPConnection) != SMTP_STATUS_OK)
    {
        *lpdwError = stSMTPConnection.dwError;

        return(SMTP_STATUS_ERROR);
    }

    return(SMTP_STATUS_OK);
}
