/*
 * Copyright (C) 2001 Apple Computer, Inc.  All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY APPLE COMPUTER, INC. ``AS IS'' AND ANY
 * EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
 * PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL APPLE COMPUTER, INC. OR
 * CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
 * EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
 * PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
 * PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY
 * OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 * OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE. 
 */
#include <kwqdebug.h>

#include <qstringlist.h>

#ifndef USING_BORROWED_QSTRINGLIST

#include <CoreFoundation/CoreFoundation.h>
#include <iostream>

// No need to CFRelease return value
static CFStringRef QStringToCFString(QString s)
{
    CFStringRef cfs = s.getCFMutableString();
    if (cfs == NULL) {
        cfs = CFSTR("");
    }
    return cfs;
}

QStringList QStringList::split(const QString &separator, const QString &s, 
				      bool allowEmptyEntries = FALSE )
{
    CFArrayRef cfresult;
    QStringList result;

    cfresult = CFStringCreateArrayBySeparatingStrings(NULL, QStringToCFString(s), QStringToCFString(separator));
    
    CFIndex cfResultSize = CFArrayGetCount(cfresult);

    for (CFIndex i = 0; i < cfResultSize; i++) {
        QString entry = QString::fromCFString((CFStringRef)CFArrayGetValueAtIndex(cfresult, i));
	if (!entry.isEmpty() || allowEmptyEntries) {
	    result.append(entry);
	}
    }

    CFRelease(cfresult);

    return result;
}
 
QStringList QStringList::split(const QChar &separator, const QString &s, 
				      bool allowEmptyEntries = FALSE )
{
    return QStringList::split(QString(separator), s, allowEmptyEntries);
}

    
QStringList::QStringList()
{
}

QStringList::QStringList(const QStringList &l) : QValueList<QString>(l)
{
    
}

QStringList::~QStringList()
{
}

QString QStringList::join(const QString &separator) const
{
    QString result;
    
    for (ConstIterator i = begin(), j = ++begin(); i != end(); ++i, ++j) {
        result += *i;
	if (j != end()) {
	    result += separator;
	}
    }

    return result;
}

QStringList &QStringList::operator=(const QStringList &l)
{
    (*this).QValueList<QString>::operator=(l);
    return *this;
}

#endif
