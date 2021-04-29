//
//  MCHTMLBodyRendererTemplateCallback.cc
//  mailcore2
//
//  Created by Paul Young on 02/07/2013.
//  Copyright (c) 2013 MailCore. All rights reserved.
//

#include "MCHTMLBodyRendererTemplateCallback.h"

using namespace mailcore;

mailcore::String * HTMLBodyRendererTemplateCallback::templateForMainHeader(MessageHeader * header)
{
    return MCSTR("<style>\
        div {\
            outline: none\
        }\
        html {\
            font-family: '-apple-system, BlinkMacSystemFont', sans-serif;\
            font-size: 105%;\
        }\
        .attachmentButton {\
          border-radius: 15px;\
          background-color: Transparent;\
          border: 1px solid #000000;\
          width: auto;\
          text-align: center;\
          padding-top: 30px;\
          padding-bottom: 30px;\
          padding-left: 35px;\
          padding-right: 35px;\
          display: block;\
          cursor: pointer;\
        }\
    </style>");

}
